defmodule MilosTrainingWeb.MyWorkoutController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.GetAssignedWorkoutWeek
  alias MilosTraining.Application.ListAssignmentMessages
  alias MilosTraining.Application.PostAssignmentMessage
  alias MilosTraining.Application.RejectAssignedWorkout
  alias MilosTraining.Application.RescheduleAssignedWorkout
  alias MilosTraining.Application.SendAthleteMessage
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Assigned Workouts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:send_message, :post_message]

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

  operation(:send_message,
    summary: "Athlete sends a message to all coaches about an assigned workout",
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
            properties: %{body: %Schema{type: :string, minLength: 1, maxLength: 1000}},
            required: [:body]
          }
        }
      }
    },
    responses: [ok: {"OK", "application/json", %Schema{type: :object}}]
  )

  def send_message(conn, params) do
    user = GuardianPlug.current_resource(conn)
    body_text = get_in(params, ["body"]) || get_in(conn.body_params, ["body"]) || ""

    context_url = "/my-workouts"

    case SendAthleteMessage.call(user.id, user.nickname, String.trim(body_text), context_url) do
      :ok -> json(conn, %{ok: true})
      {:error, _} -> {:error, :unprocessable_entity}
    end
  end

  operation(:list_messages,
    summary: "List messages for an assigned workout",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"Messages", "application/json", %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def list_messages(conn, %{"id" => assignment_id}) do
    user = GuardianPlug.current_resource(conn)

    case ListAssignmentMessages.call(assignment_id, user) do
      {:ok, messages} -> json(conn, %{messages: messages})
      {:error, :not_found} -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :forbidden}
    end
  end

  operation(:post_message,
    summary: "Post a message on an assigned workout thread",
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
            properties: %{body: %Schema{type: :string, minLength: 1, maxLength: 2000}},
            required: [:body]
          }
        }
      }
    },
    responses: [
      ok: {"Message", "application/json", %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def post_message(conn, %{id: assignment_id} = params) do
    user = GuardianPlug.current_resource(conn)
    body_text = params[:body] || get_in(conn.body_params, ["body"]) || ""

    case PostAssignmentMessage.call(assignment_id, user, body_text) do
      {:ok, message} -> json(conn, %{message: message})
      {:error, :not_found} -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, _} -> {:error, :unprocessable_entity}
    end
  end
end
