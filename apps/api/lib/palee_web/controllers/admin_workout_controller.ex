defmodule PaleeWeb.AdminWorkoutController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias Palee.Application.{
    CreateDraftWorkout,
    DeleteWorkout,
    DuplicateWorkout,
    FileWorkoutCopy,
    GetAdminWorkout,
    SetWorkoutIcon,
    ListAdminWorkouts,
    PublishWorkout,
    ReopenWorkout,
    UpdateDraftWorkout
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias PaleeWeb.Schemas.Workout, as: WorkoutSchema

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:create, :update_draft, :publish, :copy, :update_icon]

  @icon_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          properties: %{
            icon: %Schema{
              type: :string,
              nullable: true,
              maxLength: 32,
              description: "A single emoji; null resets the icon to automatic"
            }
          },
          required: [:icon]
        }
      }
    }
  }

  @folder_target_body %RequestBody{
    required: false,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          properties: %{
            folder_id: %Schema{type: :string, format: :uuid, nullable: true}
          }
        }
      }
    }
  }

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index,
    summary: "List master workouts",
    responses: [
      ok:
        {"Workouts", "application/json",
         %Schema{
           type: :object,
           properties: %{
             workouts: %Schema{
               type: :array,
               items: %Schema{type: :object, additionalProperties: true}
             }
           },
           required: [:workouts]
         }},
      unauthorized:
        {"Unauthorized", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}},
      forbidden:
        {"Forbidden", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  operation(:create,
    summary: "Create an empty workout draft, optionally inside a library folder",
    request_body: @folder_target_body,
    responses: [
      created:
        {"Draft", "application/json",
         %Schema{
           type: :object,
           properties: %{draft: %Schema{type: :object, additionalProperties: true}},
           required: [:draft]
         }}
    ]
  )

  operation(:show,
    summary: "Get an admin workout draft or published workout",
    parameters: [@id_param],
    responses: [
      ok: {"Workout", "application/json", WorkoutSchema.response_schema()},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  operation(:update_draft,
    summary: "Autosave a workout draft",
    parameters: [@id_param],
    request_body: %RequestBody{
      description: "Draft payload",
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: WorkoutSchema.draft_request_schema()
        }
      }
    },
    responses: [
      ok:
        {"Draft", "application/json",
         %Schema{
           type: :object,
           properties: %{draft: %Schema{type: :object, additionalProperties: true}},
           required: [:draft]
         }}
    ]
  )

  operation(:publish,
    summary: "Publish a workout draft",
    parameters: [@id_param],
    request_body: %RequestBody{
      description: "Optional publish payload or overrides",
      required: false,
      content: %{
        "application/json" => %MediaType{
          schema: WorkoutSchema.draft_request_schema()
        }
      }
    },
    responses: [
      ok: {"Workout", "application/json", WorkoutSchema.response_schema()},
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Schema{
           type: :object,
           properties: %{
             errors: %Schema{
               type: :object,
               additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
             }
           },
           required: [:errors]
         }}
    ]
  )

  operation(:delete,
    summary: "Hard delete a workout and dependent records",
    parameters: [@id_param],
    responses: [
      no_content: {"Deleted", "application/json", %Schema{type: :object}},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  operation(:update_library,
    summary: "Move a workout in the nested library",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{folder_id: %Schema{type: :string, format: :uuid, nullable: true}},
            required: [:folder_id]
          }
        }
      }
    },
    responses: [
      ok:
        {"Library metadata", "application/json",
         %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def index(conn, _params) do
    with {:ok, workouts} <- ListAdminWorkouts.call(conn.assigns.tenant_context) do
      json(conn, %{workouts: workouts})
    end
  end

  def create(conn, _params) do
    admin = GuardianPlug.current_resource(conn)

    case CreateDraftWorkout.call(conn.assigns.tenant_context, admin, folder_id(conn)) do
      {:ok, draft} ->
        conn
        |> put_status(:created)
        |> json(%{draft: draft})

      error ->
        error
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, workout} <- GetAdminWorkout.call(conn.assigns.tenant_context, id) do
      json(conn, %{workout: workout})
    end
  end

  def update_draft(conn, params) do
    id = params[:id] || params["id"]

    case UpdateDraftWorkout.call(conn.assigns.tenant_context, id, conn.body_params) do
      {:ok, draft} -> json(conn, %{draft: draft})
      error -> error
    end
  end

  def publish(conn, params) do
    id = params[:id] || params["id"]

    case PublishWorkout.call(conn.assigns.tenant_context, id, conn.body_params) do
      {:ok, workout} -> json(conn, %{workout: workout})
      error -> error
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- DeleteWorkout.call(conn.assigns.tenant_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  def update_library(conn, params) do
    id = params["id"] || params[:id]

    with {:ok, metadata} <-
           Palee.Workouts.update_library_metadata(
             conn.assigns.tenant_context,
             id,
             conn.body_params
           ) do
      json(conn, metadata)
    end
  end

  operation(:reopen,
    summary: "Reopen a published workout for editing",
    parameters: [@id_param],
    responses: [
      ok:
        {"Draft", "application/json",
         %Schema{
           type: :object,
           properties: %{draft: %Schema{type: :object, additionalProperties: true}},
           required: [:draft]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}},
      unprocessable_entity:
        {"Not published", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  def reopen(conn, %{"id" => id}) do
    case ReopenWorkout.call(conn.assigns.tenant_context, id) do
      {:ok, draft} -> json(conn, %{draft: draft})
      {:error, :not_found} -> {:error, :not_found}
      {:error, :not_published} -> {:error, :unprocessable_entity}
      error -> error
    end
  end

  operation(:duplicate,
    summary: "Duplicate a workout as a new draft",
    parameters: [@id_param],
    responses: [
      created:
        {"Draft", "application/json",
         %Schema{
           type: :object,
           properties: %{draft: %Schema{type: :object, additionalProperties: true}},
           required: [:draft]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  operation(:copy,
    summary: "Copy a workout into a library folder (published workouts stay published)",
    parameters: [@id_param],
    request_body: @folder_target_body,
    responses: [
      created:
        {"Copied workout", "application/json",
         %Schema{
           type: :object,
           properties: %{workout: %Schema{type: :object, additionalProperties: true}},
           required: [:workout]
         }}
    ]
  )

  def copy(conn, params) do
    id = Map.get(params, "id") || Map.get(params, :id)

    with {:ok, workout} <- FileWorkoutCopy.copy(conn.assigns.tenant_context, id, folder_id(conn)) do
      conn
      |> put_status(:created)
      |> json(%{workout: workout})
    end
  end

  operation(:update_icon,
    summary: "Set a workout's library icon, or reset it to automatic (rules + AI suggestion)",
    parameters: [@id_param],
    request_body: @icon_body,
    responses: [
      ok:
        {"Icon", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid},
             icon: %Schema{type: :string, nullable: true},
             icon_source: %Schema{type: :string, nullable: true, enum: ["ai", "coach", nil]}
           },
           required: [:id, :icon, :icon_source]
         }}
    ]
  )

  def update_icon(conn, params) do
    id = Map.get(params, "id") || Map.get(params, :id)
    icon = Map.get(conn.body_params, :icon) || Map.get(conn.body_params, "icon")

    with {:ok, result} <- SetWorkoutIcon.call(conn.assigns.tenant_context, id, icon) do
      json(conn, result)
    end
  end

  defp folder_id(conn) do
    case conn.body_params do
      %{folder_id: folder_id} -> folder_id
      %{"folder_id" => folder_id} -> folder_id
      _none -> nil
    end
  end

  def duplicate(conn, params) do
    id = Map.get(params, "id") || Map.get(params, :id)

    opts = [
      assignment_id: Map.get(conn.body_params, "assignment_id"),
      slot_id: Map.get(conn.body_params, "slot_id")
    ]

    case DuplicateWorkout.call(conn.assigns.tenant_context, id, opts) do
      {:ok, draft} ->
        conn
        |> put_status(:created)
        |> json(%{draft: draft})

      {:error, :not_found} ->
        {:error, :not_found}

      error ->
        error
    end
  end
end
