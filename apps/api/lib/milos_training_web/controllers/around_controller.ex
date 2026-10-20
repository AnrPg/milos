defmodule MilosTrainingWeb.AroundController do
  @moduledoc "Γύρω μου: nearby events, boxes, open clubs and public posts (ADR-154)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.AroundMe
  alias MilosTrainingWeb.Schemas.Around, as: S
  alias OpenApiSpex.Parameter

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Around"])
  security([%{"bearerAuth" => []}])

  operation(:search,
    summary: "Γύρω μου: each kind's nearest or soonest cards, totals and wider counts",
    description:
      "Events (soonest first), boxes with a published page (trial-takers first, then " <>
        "nearest), open clubs (nearest) and, when asked for, public posts (newest). " <>
        "Remembers the filter as your last-used Γύρω μου filter unless `remember` is false.",
    request_body: S.body(S.search_request()),
    responses: [ok: {"Sections", "application/json", S.search_response()}]
  )

  def search(conn, _params) do
    with {:ok, result} <- AroundMe.search(conn.assigns.user_context, conn.body_params),
         do: json(conn, result)
  end

  operation(:kind,
    summary: "One Γύρω μου kind, cursor-paged («Δες όλα»)",
    parameters: [
      %Parameter{name: :kind, in: :path, required: true, schema: S.kind()}
    ],
    request_body: S.body(S.kind_request()),
    responses: [ok: {"Page", "application/json", S.kind_response()}]
  )

  def kind(conn, %{"kind" => kind}) do
    with {:ok, page} <- AroundMe.kind(conn.assigns.user_context, kind, conn.body_params),
         do: json(conn, page)
  end

  operation(:pins,
    summary: "Map pins inside a viewport («Ψάξε εδώ»), same filter, capped",
    request_body: S.body(S.pins_request()),
    responses: [ok: {"Pins", "application/json", S.pins_response()}]
  )

  def pins(conn, _params) do
    with {:ok, pins} <- AroundMe.pins(conn.assigns.user_context, conn.body_params),
         do: json(conn, pins)
  end
end
