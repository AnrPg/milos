defmodule PaleeWeb.PtSquadController do
  @moduledoc "PT squads in your gym's club (ADR-168)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.PtSquads
  alias PaleeWeb.Schemas.PtSquads, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @uuid %Schema{type: :string, format: :uuid}
  @id %Parameter{name: :id, in: :path, required: true, schema: @uuid}
  @user_id %Parameter{name: :user_id, in: :path, required: true, schema: @uuid}
  @squad {"Squad", "application/json", S.squad_response()}
  @outcome {"Outcome", "application/json", S.outcome_response()}

  operation(:index,
    summary: "Squads you coach or are in, invitations waiting for you, and clients to invite",
    responses: [ok: {"Squads", "application/json", S.overview_response()}]
  )

  def index(conn, _params) do
    with {:ok, result} <- PtSquads.overview(conn.assigns.tenant_context),
         do: json(conn, result)
  end

  operation(:create,
    summary: "Coaches: start a squad, optionally inviting some of your clients",
    request_body: S.body(S.create_request()),
    responses: [created: @squad]
  )

  def create(conn, _params) do
    with {:ok, squad} <- PtSquads.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{squad: squad})
    end
  end

  operation(:show,
    summary: "A squad with its people (its coach also sees open invitations)",
    parameters: [@id],
    responses: [ok: @squad]
  )

  def show(conn, %{id: id}), do: reply(conn, PtSquads.show(conn.assigns.tenant_context, id))

  operation(:update,
    summary: "Coach: rename or describe the squad",
    parameters: [@id],
    request_body: S.body(S.update_request()),
    responses: [ok: @squad]
  )

  def update(conn, %{id: id}),
    do: reply(conn, PtSquads.update(conn.assigns.tenant_context, id, conn.body_params))

  operation(:invite,
    summary: "Coach: invite some of your active clients",
    parameters: [@id],
    request_body: S.body(S.invite_request()),
    responses: [ok: @squad]
  )

  def invite(conn, %{id: id}),
    do: reply(conn, PtSquads.invite(conn.assigns.tenant_context, id, conn.body_params.user_ids))

  operation(:answer,
    summary: "Accept or decline an invitation to a squad",
    parameters: [@id],
    request_body: S.body(S.answer_request()),
    responses: [
      ok:
        {"Squad or outcome", "application/json",
         %Schema{oneOf: [S.squad_response(), S.outcome_response()]}}
    ]
  )

  def answer(conn, %{id: id}) do
    case PtSquads.answer(conn.assigns.tenant_context, id, conn.body_params.accept) do
      {:ok, %{outcome: _} = outcome} -> json(conn, outcome)
      other -> reply(conn, other)
    end
  end

  operation(:leave,
    summary: "Leave a squad",
    parameters: [@id],
    responses: [ok: @outcome]
  )

  def leave(conn, %{id: id}) do
    with {:ok, outcome} <- PtSquads.leave(conn.assigns.tenant_context, id),
         do: json(conn, outcome)
  end

  operation(:remove_member,
    summary: "Coach: remove a member, or withdraw an invitation",
    parameters: [@id, @user_id],
    responses: [ok: @squad]
  )

  def remove_member(conn, %{id: id, user_id: user_id}),
    do: reply(conn, PtSquads.remove_member(conn.assigns.tenant_context, id, user_id))

  operation(:archive,
    summary: "Coach (or the gym's managers): archive the squad",
    parameters: [@id],
    responses: [ok: @outcome]
  )

  def archive(conn, %{id: id}) do
    with {:ok, outcome} <- PtSquads.archive(conn.assigns.tenant_context, id),
         do: json(conn, outcome)
  end

  operation(:reopen,
    summary: "Coach: bring back an archived squad",
    parameters: [@id],
    responses: [ok: @squad]
  )

  def reopen(conn, %{id: id}), do: reply(conn, PtSquads.reopen(conn.assigns.tenant_context, id))

  defp reply(conn, {:ok, squad}), do: json(conn, %{squad: squad})
  defp reply(_conn, error), do: error
end
