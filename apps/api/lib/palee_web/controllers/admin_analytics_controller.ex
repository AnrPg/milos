defmodule PaleeWeb.AdminAnalyticsController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.GetAdminAnalyticsSummary
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Analytics"])
  security([%{"bearerAuth" => []}])

  @summary_schema %Schema{type: :object, additionalProperties: true}

  operation(:summary,
    summary: "Fetch Phase 8 analytics summary from persisted facts and aggregates",
    parameters: [
      %Parameter{
        name: :days,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 365}
      }
    ],
    responses: [ok: {"Analytics summary", "application/json", @summary_schema}]
  )

  def summary(conn, params) do
    with {:ok, payload} <- GetAdminAnalyticsSummary.call(conn.assigns.tenant_context, params) do
      json(conn, payload)
    end
  end
end
