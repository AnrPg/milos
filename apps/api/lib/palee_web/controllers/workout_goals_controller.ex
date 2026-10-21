defmodule PaleeWeb.WorkoutGoalsController do
  @moduledoc "A member's read of a published workout's visible WOD goals (ADR-163)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.GetMemberWorkoutGoals
  alias PaleeWeb.Schemas.WorkoutGoals
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Workouts"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  operation(:show,
    summary: "A published workout's WOD goals, when the coach made them visible",
    description: "goals is null when none are saved or the coach keeps them hidden.",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        description: "Workout ID",
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"WOD goals", "application/json", WorkoutGoals.member_response()},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- GetMemberWorkoutGoals.call(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end
end
