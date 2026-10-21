defmodule MilosTrainingWeb.AdminWorkoutGoalsController do
  @moduledoc """
  Staff read and save of a workout's WOD goals, and the coach totals of
  «τι ένιωσες» on a workout or a scheduled class (ADR-163).
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{GetGoalFeedbackSummary, GetWorkoutGoals, SaveWorkoutGoals}
  alias MilosTrainingWeb.Schemas.WorkoutGoals
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Workouts"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @id %Parameter{
    name: :id,
    in: :path,
    description: "Workout ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @error %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:error]
  }

  operation(:show,
    summary: "A workout's WOD goals and the live suggestion",
    description:
      "Saved goals, or the suggestion from the workout's exercises (saved=false) when none are saved. Drafts included.",
    parameters: [@id],
    responses: [
      ok: {"WOD goals", "application/json", WorkoutGoals.staff_response()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- GetWorkoutGoals.call(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:update,
    summary: "Save a workout's WOD goals",
    parameters: [@id],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: WorkoutGoals.save_request()}}
    },
    responses: [
      ok: {"WOD goals", "application/json", WorkoutGoals.staff_response()},
      not_found: {"Not found", "application/json", @error},
      unprocessable_entity: {"Invalid goals", "application/json", @error}
    ]
  )

  def update(conn, %{id: id}) do
    with {:ok, result} <-
           SaveWorkoutGoals.call(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:feedback_summary,
    summary: "Coach totals of «τι ένιωσες» on a workout",
    description:
      "Counts only feedback on non-voided entries whose visibility reaches the caller as a coach; shown only from 3 entries.",
    parameters: [@id],
    responses: [
      ok: {"Goal feedback summary", "application/json", WorkoutGoals.feedback_summary()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def feedback_summary(conn, %{id: id}) do
    with {:ok, result} <- GetGoalFeedbackSummary.for_workout(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:class_feedback_summary,
    summary: "Coach totals of «τι ένιωσες» on a scheduled class",
    description:
      "Entries logged from the class or timed from its bookings, whatever workout version they followed; same rules as the workout summary.",
    parameters: [%{@id | description: "Scheduled class (slot) ID"}],
    responses: [
      ok: {"Goal feedback summary", "application/json", WorkoutGoals.feedback_summary()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def class_feedback_summary(conn, %{id: id}) do
    with {:ok, result} <-
           GetGoalFeedbackSummary.for_scheduled_class(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end
end
