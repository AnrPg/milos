defmodule MilosTrainingWeb.GoalFeedbackController do
  @moduledoc "«Τι ένιωσες» on the member's own executions and training-log entries (ADR-163)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{GetGoalFeedback, SaveGoalFeedback}
  alias MilosTrainingWeb.Schemas.WorkoutGoals
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Journal"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @params [
    %Parameter{
      name: :entry_kind,
      in: :path,
      required: true,
      schema: %Schema{type: :string, enum: ["execution", "training_log"]}
    },
    %Parameter{
      name: :entry_id,
      in: :path,
      required: true,
      schema: %Schema{type: :string, format: :uuid}
    }
  ]

  @error %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:error]
  }

  operation(:show,
    summary: "The goals of an entry's workout and what the member felt",
    description:
      "Only for the member's own entry. goals is null unless the coach made them visible; feedback is null until saved.",
    parameters: @params,
    responses: [
      ok: {"Goal feedback", "application/json", WorkoutGoals.feedback_response()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def show(conn, %{entry_kind: kind, entry_id: id}) do
    with {:ok, result} <- GetGoalFeedback.call(conn.assigns.tenant_context, kind, id) do
      json(conn, result)
    end
  end

  operation(:update,
    summary: "Save what the member felt after one of their entries",
    parameters: @params,
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: WorkoutGoals.feedback_request()}}
    },
    responses: [
      ok: {"Goal feedback", "application/json", WorkoutGoals.feedback_response()},
      not_found: {"Not found", "application/json", @error},
      unprocessable_entity: {"Invalid feedback", "application/json", @error}
    ]
  )

  def update(conn, %{entry_kind: kind, entry_id: id}) do
    with {:ok, result} <-
           SaveGoalFeedback.call(conn.assigns.tenant_context, kind, id, conn.body_params) do
      json(conn, result)
    end
  end
end
