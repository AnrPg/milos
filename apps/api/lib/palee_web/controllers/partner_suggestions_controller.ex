defmodule PaleeWeb.PartnerSuggestionsController do
  @moduledoc """
  «Κλείστε μαζί» for a Partners match (ADR-280 §4): the suggestions,
  proposing one as a plan in the conversation, «Δεν ταιριάζει» feedback,
  and the vendors' daily counters.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Parameter
  alias Palee.Application.PartnerSuggestions
  alias PaleeWeb.Schemas.PartnerSuggestions, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Partners"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  defp ctx(conn), do: conn.assigns.user_context

  operation(:index,
    summary: "«Κλείστε μαζί»: up to three activities that suit you both",
    description:
      "Classes of a box you both belong to, and events and trial classes near both of " <>
        "you, in the next 7 days with free places. Says only whether you or your partner " <>
        "booked each one.",
    parameters: [@id],
    responses: [ok: {"Suggestions", "application/json", S.suggestions()}]
  )

  def index(conn, %{id: id}) do
    with {:ok, result} <- PartnerSuggestions.suggestions(ctx(conn), id), do: json(conn, result)
  end

  operation(:propose,
    summary: "Propose a suggestion as a plan in the conversation",
    parameters: [@id],
    request_body: S.body(S.plan_request()),
    responses: [
      created: {"Message", "application/json", PaleeWeb.Schemas.Partners.message_response()}
    ]
  )

  def propose(conn, %{id: id}) do
    with {:ok, message} <- PartnerSuggestions.propose(ctx(conn), id, conn.body_params) do
      conn |> put_status(:created) |> json(%{message: message})
    end
  end

  operation(:feedback,
    summary: "«Δεν ταιριάζει»: why a suggestion does not suit you",
    parameters: [@id],
    request_body: S.body(S.feedback_request()),
    responses: [ok: {"Feedback", "application/json", S.feedback_response()}]
  )

  def feedback(conn, %{id: id}) do
    with {:ok, result} <- PartnerSuggestions.feedback(ctx(conn), id, conn.body_params),
         do: json(conn, result)
  end

  operation(:stats,
    summary: "Daily «Κλείστε μαζί» counters of the last 30 days (vendors)",
    responses: [ok: {"Stats", "application/json", S.stats()}]
  )

  def stats(conn, _params) do
    with {:ok, stats} <- PartnerSuggestions.stats(conn.assigns.platform_context),
         do: json(conn, stats)
  end
end
