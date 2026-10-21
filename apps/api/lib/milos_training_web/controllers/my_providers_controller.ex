defmodule MilosTrainingWeb.MyProvidersController do
  @moduledoc """
  Box ▾ and the merged «Σήμερα» (ADR-162): everyone who provides the
  member's training, the provider Box opens on, and today's items from all
  of them.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{MyProviders, MyToday}
  alias MilosTrainingWeb.Schemas.CrossProvider
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  operation(:index,
    summary: "Your providers (gyms and independent coaches), active and former",
    responses: [ok: {"Providers", "application/json", CrossProvider.providers_response()}]
  )

  def index(conn, _params) do
    with {:ok, providers} <- MyProviders.call(conn.assigns.user_context) do
      json(conn, providers)
    end
  end

  operation(:select,
    summary: "Remember the provider Box opens on",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: CrossProvider.select_request()}}
    },
    responses: [
      ok: {"Providers", "application/json", CrossProvider.providers_response()},
      unprocessable_entity: {"Not an active provider", "application/json", %Schema{type: :object}}
    ]
  )

  def select(conn, _params) do
    with {:ok, providers} <-
           MyProviders.select(conn.assigns.user_context, conn.body_params.organization_id) do
      json(conn, providers)
    end
  end

  operation(:today,
    summary: "Today across every provider, in time order, each with its source",
    parameters: [
      %Parameter{
        name: :date,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date}
      },
      %Parameter{
        name: :timezone,
        in: :query,
        required: false,
        description: "IANA zone the day is counted in (UTC by default)",
        schema: %Schema{type: :string}
      }
    ],
    responses: [ok: {"Today", "application/json", CrossProvider.today_response()}]
  )

  def today(conn, params) do
    params =
      params
      |> Map.take([:date, :timezone])
      |> Map.new(fn
        {key, %Date{} = date} -> {to_string(key), Date.to_iso8601(date)}
        {key, value} -> {to_string(key), value}
      end)

    with {:ok, today} <- MyToday.call(conn.assigns.user_context, params) do
      json(conn, today)
    end
  end
end
