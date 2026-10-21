defmodule PaleeWeb.MyScalingController do
  @moduledoc """
  The member's coach-approved adaptation of a workout (ADR-174). Only an
  approved suggestion is ever returned; otherwise `scaling` is null.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ScalingSuggestions
  alias PaleeWeb.Schemas.Scaling, as: ScalingSchemas
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Workouts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "The current user's coach-approved adaptation of a workout",
    parameters: [
      %Parameter{
        name: :workout_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [ok: {"Adaptation", "application/json", ScalingSchemas.member_response()}]
  )

  def show(conn, %{workout_id: workout_id}) do
    with {:ok, scaling} <- ScalingSuggestions.for_member(conn.assigns.tenant_context, workout_id) do
      json(conn, %{scaling: scaling})
    end
  end
end
