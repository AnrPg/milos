defmodule MilosTrainingWeb.AdminSeasonController do
  @moduledoc "Staff build and sell seasons and answer requests for places (ADR-167)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.Seasons
  alias MilosTrainingWeb.Schemas.Seasons, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Seasons"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    not_found: {"No such season or enrollment", "application/json", %Schema{type: :object}},
    conflict: {"The season can't take this step now", "application/json", %Schema{type: :object}},
    unprocessable_entity: {"Invalid season", "application/json", %Schema{type: :object}}
  ]

  operation(:index,
    summary: "The gym's seasons with their place counts",
    responses: [ok: {"Seasons", "application/json", S.staff_list()}]
  )

  def index(conn, _params), do: json(conn, Seasons.list(conn.assigns.tenant_context))

  operation(:show,
    summary: "One season with every request and participant",
    parameters: [@id],
    responses: [ok: {"Season", "application/json", S.staff_response()}] ++ @refused
  )

  def show(conn, %{id: id}) do
    with {:ok, season} <- Seasons.show(conn.assigns.tenant_context, id),
         do: json(conn, %{season: season})
  end

  operation(:create,
    summary: "Create a season (a draft unless published straight away)",
    request_body: S.body(S.offering_input([:title, :starts_on, :weeks, :capacity, :price_cents])),
    responses: [created: {"Season", "application/json", S.staff_response()}] ++ @refused
  )

  def create(conn, _params) do
    with {:ok, season} <- Seasons.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{season: season})
    end
  end

  operation(:update,
    summary: "Change, publish or cancel a season",
    description:
      "Start date, weeks and programme are locked once a participant is confirmed. " <>
        "Cancelling closes every request and place and archives the season's channel.",
    parameters: [@id],
    request_body: S.body(S.offering_input()),
    responses: [ok: {"Season", "application/json", S.staff_response()}] ++ @refused
  )

  def update(conn, %{id: id}) do
    with {:ok, season} <- Seasons.update(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, %{season: season})
  end

  operation(:confirm,
    summary: "Confirm a request: package, #season channel and programme",
    parameters: [@id],
    responses: [ok: {"Season", "application/json", S.staff_response()}] ++ @refused
  )

  def confirm(conn, %{id: id}) do
    with {:ok, season} <- Seasons.confirm(conn.assigns.tenant_context, id),
         do: json(conn, %{season: season})
  end

  operation(:decline,
    summary: "Decline a request, with an optional reason the member sees",
    parameters: [@id],
    request_body: S.body(S.decline_request()),
    responses: [ok: {"Season", "application/json", S.staff_response()}] ++ @refused
  )

  def decline(conn, %{id: id}) do
    reason = Map.get(conn.body_params, :reason)

    with {:ok, season} <- Seasons.decline(conn.assigns.tenant_context, id, reason),
         do: json(conn, %{season: season})
  end

  operation(:remove,
    summary: "Take a member out of the season (their programme from today on goes)",
    parameters: [@id],
    responses: [ok: {"Season", "application/json", S.staff_response()}] ++ @refused
  )

  def remove(conn, %{id: id}) do
    with {:ok, season} <- Seasons.remove(conn.assigns.tenant_context, id),
         do: json(conn, %{season: season})
  end
end
