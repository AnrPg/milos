defmodule MilosTrainingWeb.AdminAssignedWorkoutController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{AssignWorkout, DeleteAssignedWorkout, UpdateAssignedWorkout}
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Assigned Workouts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:create, :update]

  operation(:create,
    summary: "Assign a published workout to one or more athletes",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              master_workout_id: %Schema{type: :string, format: :uuid},
              athlete_ids: %Schema{
                type: :array,
                items: %Schema{type: :string, format: :uuid}
              },
              scheduled_for: %Schema{type: :string, format: :date},
              admin_notes: %Schema{type: :string}
            },
            required: [:master_workout_id, :athlete_ids, :scheduled_for]
          }
        }
      }
    },
    responses: [
      created:
        {"Assigned workout", "application/json",
         %Schema{
           type: :object,
           properties: %{assignment: %Schema{type: :object, additionalProperties: true}},
           required: [:assignment]
         }}
    ]
  )

  operation(:update,
    summary: "Update an assigned workout",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              scheduled_for: %Schema{type: :string, format: :date},
              athlete_ids: %Schema{
                type: :array,
                items: %Schema{type: :string, format: :uuid}
              },
              admin_notes: %Schema{type: :string}
            },
            required: [:scheduled_for, :athlete_ids]
          }
        }
      }
    },
    responses: [
      ok:
        {"Assigned workout", "application/json",
         %Schema{
           type: :object,
           properties: %{assignment: %Schema{type: :object, additionalProperties: true}},
           required: [:assignment]
         }}
    ]
  )

  operation(:delete,
    summary: "Delete an assigned workout",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      no_content: {"Deleted", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, _params) do
    case AssignWorkout.call(conn.body_params) do
      {:ok, assignment} ->
        conn
        |> put_status(:created)
        |> json(%{assignment: assignment})

      error ->
        error
    end
  end

  def update(conn, params) do
    id = Map.get(params, "id") || Map.get(params, :id)

    case UpdateAssignedWorkout.call(id, conn.body_params) do
      {:ok, assignment} -> json(conn, %{assignment: assignment})
      error -> error
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- DeleteAssignedWorkout.call(id) do
      send_resp(conn, :no_content, "")
    end
  end
end
