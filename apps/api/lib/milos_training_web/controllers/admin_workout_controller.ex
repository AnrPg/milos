defmodule MilosTrainingWeb.AdminWorkoutController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.{CreateDraftWorkout, PublishWorkout, UpdateDraftWorkout}
  alias MilosTraining.Workouts
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:create, :publish]

  @score_schema %Schema{
    type: :object,
    properties: %{
      type: %Schema{type: :string},
      unit: %Schema{type: :string},
      label: %Schema{type: :string}
    }
  }

  @timer_schema %Schema{
    type: :object,
    properties: %{
      type: %Schema{type: :string},
      interval_seconds: %Schema{type: :integer},
      duration_seconds: %Schema{type: :integer},
      rounds: %Schema{type: :integer},
      work_seconds: %Schema{type: :integer},
      rest_seconds: %Schema{type: :integer}
    }
  }

  @variation_schema %Schema{
    type: :object,
    properties: %{
      scale_level_slug: %Schema{type: :string},
      sets: %Schema{type: :integer},
      exercise_name_override: %Schema{type: :string},
      prescription_value: %Schema{type: :integer},
      prescription_unit: %Schema{type: :string},
      load_value: %Schema{type: :integer},
      load_mode: %Schema{type: :string},
      excluded: %Schema{type: :boolean}
    },
    required: [:scale_level_slug]
  }

  @exercise_schema %Schema{
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      sets: %Schema{type: :integer},
      prescription_value: %Schema{type: :integer},
      prescription_unit: %Schema{type: :string},
      load_value: %Schema{type: :integer},
      load_mode: %Schema{type: :string},
      superset_group_id: %Schema{type: :string, format: :uuid},
      hr_zone: %Schema{type: :integer},
      tempo: %Schema{type: :string},
      rest_seconds: %Schema{type: :integer},
      cluster_rest_seconds: %Schema{type: :integer},
      rest_pause_seconds: %Schema{type: :integer},
      pacing: %Schema{type: :integer},
      interval_assignment: %Schema{type: :integer},
      order: %Schema{type: :integer},
      variations: %Schema{type: :array, items: @variation_schema}
    },
    required: [:name, :order]
  }

  @section_schema %Schema{
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      order: %Schema{type: :integer},
      scoreable: %Schema{type: :boolean},
      score_config: @score_schema,
      timer_config: @timer_schema,
      exercises: %Schema{type: :array, items: @exercise_schema}
    },
    required: [:name, :order, :exercises]
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
    parameters: [
      %OpenApiSpex.Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
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
                enum: Enum.map(MilosTraining.Workouts.MasterWorkout.types(), &to_string/1)
              },
              sections: %Schema{type: :array, items: @section_schema}
            }
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
    request_body: %RequestBody{
      description: "Optional publish overrides",
      required: false,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              title: %Schema{type: :string},
              type: %Schema{
                type: :string,
                enum: Enum.map(MilosTraining.Workouts.MasterWorkout.types(), &to_string/1)
              }
            }
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

  def index(conn, _params) do
    json(conn, %{workouts: Workouts.list_workouts()})
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
    case Workouts.get_workout_for_admin(id) do
      nil -> {:error, :not_found}
      workout -> json(conn, %{workout: workout})
    end
  end

  def update_draft(conn, params) do
    id = Map.get(params, "id") || get_in(conn.path_params, ["id"])

    case UpdateDraftWorkout.call(id, conn.body_params) do
      {:ok, draft} -> json(conn, %{draft: draft})
      error -> error
    end
  end

  def publish(conn, params) do
    id = Map.get(params, "id") || get_in(conn.path_params, ["id"])

    case PublishWorkout.call(id, conn.body_params) do
      {:ok, workout} -> json(conn, %{workout: workout})
      error -> error
    end
  end
end
