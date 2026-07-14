defmodule MilosTrainingWeb.AdminAnalyticsController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.GetAdminAnalyticsSummary
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

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
    with {:ok, payload} <- GetAdminAnalyticsSummary.call(params) do
      json(conn, payload)
    end
  end
end
