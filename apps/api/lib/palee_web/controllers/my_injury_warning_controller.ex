defmodule PaleeWeb.MyInjuryWarningController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{AcknowledgeMyInjuryWarnings, GetMyWorkoutInjuryWarnings}
  alias PaleeWeb.Schemas.InjuryWarnings
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Wellbeing"])
  security([%{"bearerAuth" => []}])

  @workout_id %Parameter{
    name: :workout_id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  operation(:show,
    summary: "The current user's injury safety warnings for a workout",
    description:
      "Informational only (ADR-124): includes the user's own personal injuries; never blocks starting the workout.",
    parameters: [
      @workout_id,
      %Parameter{
        name: :surface,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: InjuryWarnings.self_surfaces()}
      },
      %Parameter{
        name: :source_context_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :scale,
        in: :query,
        required: false,
        schema: InjuryWarnings.scale()
      }
    ],
    responses: [
      ok: {"Injury warnings", "application/json", InjuryWarnings.self_result()}
    ]
  )

  def show(conn, params) do
    with {:ok, result} <-
           GetMyWorkoutInjuryWarnings.call(
             conn.assigns.tenant_context,
             workout_id(params),
             Map.take(params, [:surface, :source_context_id, :scale])
           ) do
      json(conn, result)
    end
  end

  operation(:acknowledge,
    summary: "Acknowledge the current user's injury safety warnings for a workout",
    parameters: [@workout_id],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: InjuryWarnings.self_ack_request()}}
    },
    responses: [
      ok: {"Acknowledged", "application/json", InjuryWarnings.self_ack()}
    ]
  )

  def acknowledge(conn, params) do
    with {:ok, result} <-
           AcknowledgeMyInjuryWarnings.call(
             conn.assigns.tenant_context,
             workout_id(params),
             conn.body_params
           ) do
      json(conn, result)
    end
  end

  defp workout_id(params), do: params[:workout_id] || params["workout_id"]
end
