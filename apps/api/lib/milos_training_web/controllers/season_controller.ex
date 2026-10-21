defmodule MilosTrainingWeb.SeasonController do
  @moduledoc "A member's seasons in `Box › Συνδρομή`: the list, a request and its withdrawal (ADR-167)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.Seasons
  alias MilosTrainingWeb.Schemas.Seasons, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Seasons"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    not_found: {"No such season", "application/json", %Schema{type: :object}},
    conflict: {"The season can't take this step now", "application/json", %Schema{type: :object}},
    unprocessable_entity: {"Not possible", "application/json", %Schema{type: :object}}
  ]

  operation(:index,
    summary: "The gym's open seasons and the ones you hold a place in",
    responses: [ok: {"Seasons", "application/json", S.member_list()}]
  )

  def index(conn, _params), do: json(conn, Seasons.member_list(conn.assigns.tenant_context))

  operation(:request,
    summary: "Ask for a place (the waitlist when the season is full); staff confirm",
    parameters: [@id],
    responses: [ok: {"Season", "application/json", S.member_response()}] ++ @refused
  )

  def request(conn, %{id: id}) do
    with {:ok, season} <- Seasons.request(conn.assigns.tenant_context, id),
         do: json(conn, %{season: season})
  end

  operation(:cancel,
    summary: "Withdraw your request or waitlist place",
    description: "A confirmed place is settled with the box.",
    parameters: [@id],
    responses: [ok: {"Season", "application/json", S.member_response()}] ++ @refused
  )

  def cancel(conn, %{id: id}) do
    with {:ok, season} <- Seasons.cancel(conn.assigns.tenant_context, id),
         do: json(conn, %{season: season})
  end
end
