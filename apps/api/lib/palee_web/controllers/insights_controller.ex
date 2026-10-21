defmodule PaleeWeb.InsightsController do
  @moduledoc """
  The Πρόοδος insights slot (ADR-166): the member's own findings from their
  sleep, water, cravings, sessions and PRs, at most a few at a time, each
  dismissible, none before there is enough data.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.GetMyInsights
  alias PaleeWeb.Schemas.Insights
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Progress"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @error {"Error", "application/json",
          %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}

  operation(:show,
    summary: "Your insights (indicators, never medical advice)",
    responses: [ok: {"Insights", "application/json", Insights.response()}]
  )

  def show(conn, _params) do
    with {:ok, insights} <- GetMyInsights.call(conn.assigns.user_context) do
      json(conn, insights)
    end
  end

  operation(:dismiss,
    summary: "Hide one insight until its finding changes",
    parameters: [
      %Parameter{
        name: :rule,
        in: :path,
        required: true,
        schema: %Schema{
          type: :string,
          enum: ["sleep_prs", "sleep_effort", "time_of_day", "cravings", "hydration"]
        }
      }
    ],
    responses: [
      ok: {"Insights", "application/json", Insights.response()},
      not_found: @error
    ]
  )

  def dismiss(conn, %{rule: rule}) do
    with {:ok, insights} <- GetMyInsights.dismiss(conn.assigns.user_context, rule) do
      json(conn, insights)
    end
  end

  operation(:restore,
    summary: "Show every dismissed insight again",
    responses: [ok: {"Insights", "application/json", Insights.response()}]
  )

  def restore(conn, _params) do
    with {:ok, insights} <- GetMyInsights.restore(conn.assigns.user_context) do
      json(conn, insights)
    end
  end
end
