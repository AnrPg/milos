defmodule MilosTrainingWeb.MyWorkoutController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.GetAssignedWorkoutWeek
  alias MilosTraining.Application.RejectAssignedWorkout
  alias MilosTraining.Application.RequestWorkoutAssignment
  alias MilosTraining.Application.RescheduleAssignedWorkout
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Assigned Workouts"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary:
      "List assigned workouts for the current athlete or all athlete assignments for admins",
    parameters: [
      %Parameter{
        name: :start_date,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date}
      }
    ],
    responses: [
      ok:
        {"Assigned workouts", "application/json",
         %Schema{
           type: :object,
           properties: %{
             start_date: %Schema{type: :string, format: :date},
             end_date: %Schema{type: :string, format: :date},
             assignments: %Schema{
               type: :array,
               items: %Schema{type: :object, additionalProperties: true}
             }
           },
           required: [:start_date, :end_date, :assignments]
         }}
    ]
  )

  def index(conn, params) do
    user = GuardianPlug.current_resource(conn)

    case GetAssignedWorkoutWeek.call(user, params) do
      {:ok, payload} -> json(conn, payload)
      error -> error
    end
  end

  operation(:reject,
    summary: "Athlete rejects an assigned workout",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Rejection result", "application/json",
         %Schema{type: :object, additionalProperties: true}},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Already rejected", "application/json", %Schema{type: :object}}
    ]
  )

  def reject(conn, %{"id" => assignment_id}) do
    user = GuardianPlug.current_resource(conn)

    case RejectAssignedWorkout.call(assignment_id, user.id) do
      {:ok, assignment} -> json(conn, %{assignment: assignment})
      {:error, :not_found} -> {:error, :not_found}
      {:error, :already_rejected} -> {:error, :unprocessable_entity}
      {:error, _} -> {:error, :unprocessable_entity}
    end
  end

  operation(:reschedule,
    summary: "Athlete reschedules an assigned workout to a new date",
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
            properties: %{scheduled_for: %Schema{type: :string, format: :date}},
            required: [:scheduled_for]
          }
        }
      }
    },
    responses: [
      ok:
        {"Reschedule result", "application/json",
         %Schema{type: :object, additionalProperties: true}},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid date", "application/json", %Schema{type: :object}}
    ]
  )

  def reschedule(conn, %{"id" => assignment_id} = params) do
    user = GuardianPlug.current_resource(conn)
    new_date = params["scheduled_for"] || ""

    case RescheduleAssignedWorkout.call(assignment_id, user.id, new_date) do
      {:ok, assignment} -> json(conn, %{assignment: assignment})
      {:error, :not_found} -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, :past_date} -> {:error, :unprocessable_entity}
      {:error, _} -> {:error, :unprocessable_entity}
    end
  end

  operation(:request_assignment,
    summary: "Athlete requests a workout assignment for a specific date",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              requested_for: %Schema{type: :string, format: :date},
              note: %Schema{type: :string, maxLength: 500}
            },
            required: [:requested_for]
          }
        }
      }
    },
    responses: [
      accepted:
        {"Workout assignment request accepted", "application/json",
         %Schema{
           type: :object,
           properties: %{
             requested_for: %Schema{type: :string, format: :date},
             notified_admins: %Schema{type: :integer}
           },
           required: [:requested_for, :notified_admins]
         }},
      forbidden:
        {"Only athletes can request assignments", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid or past date", "application/json", %Schema{type: :object}}
    ]
  )

  def request_assignment(conn, params) do
    user = GuardianPlug.current_resource(conn)

    case RequestWorkoutAssignment.call(user, params) do
      {:ok, payload} ->
        conn
        |> put_status(:accepted)
        |> json(%{
          requested_for: Date.to_iso8601(payload.requested_for),
          notified_admins: payload.notified_admins
        })

      {:error, :forbidden} ->
        {:error, :forbidden}

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid workout assignment request"})
    end
  end
end
