defmodule MilosTrainingWeb.AdminWorkoutController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    CreateDraftWorkout,
    DeleteWorkout,
    DuplicateWorkout,
    GetAdminWorkout,
    ListAdminWorkouts,
    PublishWorkout,
    ReopenWorkout,
    UpdateDraftWorkout
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:create, :update_draft, :publish]

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
    summary: "Create an empty workout draft",
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
      ok:
        {"Workout", "application/json",
         %Schema{
           type: :object,
           properties: %{workout: %Schema{type: :object, additionalProperties: true}},
           required: [:workout]
         }},
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
          schema: %Schema{
            type: :object,
            properties: %{
              title: %Schema{type: :string},
              type: %Schema{
                type: :string,
                enum: Enum.map(MilosTraining.Workouts.MasterWorkout.types(), &to_string/1),
                nullable: true
              },
              sections: %Schema{
                type: :array,
                items: %Schema{type: :object, additionalProperties: true}
              }
            },
            additionalProperties: true
          }
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
          schema: %Schema{
            type: :object,
            properties: %{
              title: %Schema{type: :string},
              type: %Schema{
                type: :string,
                enum: Enum.map(MilosTraining.Workouts.MasterWorkout.types(), &to_string/1),
                nullable: true
              },
              sections: %Schema{
                type: :array,
                items: %Schema{type: :object, additionalProperties: true}
              }
            },
            additionalProperties: true
          }
        }
      }
    },
    responses: [
      ok:
        {"Workout", "application/json",
         %Schema{
           type: :object,
           properties: %{workout: %Schema{type: :object, additionalProperties: true}},
           required: [:workout]
         }},
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

  def index(conn, _params) do
    with {:ok, workouts} <- ListAdminWorkouts.call() do
      json(conn, %{workouts: workouts})
    end
  end

  def create(conn, _params) do
    admin = GuardianPlug.current_resource(conn)

    case CreateDraftWorkout.call(admin) do
      {:ok, draft} ->
        conn
        |> put_status(:created)
        |> json(%{draft: draft})

      error ->
        error
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, workout} <- GetAdminWorkout.call(id) do
      json(conn, %{workout: workout})
    end
  end

  def update_draft(conn, params) do
    id = params[:id] || params["id"]

    case UpdateDraftWorkout.call(id, conn.body_params) do
      {:ok, draft} -> json(conn, %{draft: draft})
      error -> error
    end
  end

  def publish(conn, params) do
    id = params[:id] || params["id"]

    case PublishWorkout.call(id, conn.body_params) do
      {:ok, workout} -> json(conn, %{workout: workout})
      error -> error
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- DeleteWorkout.call(id) do
      send_resp(conn, :no_content, "")
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
    case ReopenWorkout.call(id) do
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

  def duplicate(conn, params) do
    id = Map.get(params, "id") || Map.get(params, :id)

    opts = [
      assignment_id: Map.get(conn.body_params, "assignment_id"),
      slot_id: Map.get(conn.body_params, "slot_id")
    ]

    case DuplicateWorkout.call(id, opts) do
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
