defmodule PaleeWeb.PlatformBusinessAccountController do
  @moduledoc """
  ADR-184, the vendors' console: the queue of requests and demo businesses,
  decisions, and activation links.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.{BusinessActivation, BusinessRequests}
  alias PaleeWeb.BusinessAccountJSON
  alias PaleeWeb.Schemas.BusinessAccounts, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Platform business accounts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:queue,
    summary: "Pending requests and businesses in demo mode (vendors)",
    responses: [ok: {"Queue", "application/json", S.queue()}]
  )

  def queue(conn, _params) do
    with {:ok, queue} <- BusinessRequests.queue(conn.assigns.platform_context) do
      json(conn, BusinessAccountJSON.queue(queue))
    end
  end

  operation(:decide,
    summary: "Approve or decline a request (vendors)",
    description:
      "Approving a conversion creates the business in demo mode; approving an " <>
        "activation request issues the activation link for the requester.",
    parameters: [@id],
    request_body: S.decision_body(),
    responses: [ok: {"Decision", "application/json", S.decision_result()}]
  )

  def decide(conn, %{id: id}) do
    with {:ok, result} <-
           BusinessRequests.decide(conn.assigns.platform_context, id, conn.body_params) do
      json(conn, BusinessAccountJSON.decision(result))
    end
  end

  operation(:issue_link,
    summary: "Issue the activation link of a demo business for one account (vendors)",
    parameters: [@id],
    request_body: S.issue_link_body(),
    responses: [created: {"Link", "application/json", S.activation_link()}]
  )

  def issue_link(conn, %{id: organization_id}) do
    with {:ok, issued} <-
           BusinessActivation.issue_link(
             conn.assigns.platform_context,
             organization_id,
             conn.body_params
           ) do
      conn |> put_status(:created) |> json(BusinessAccountJSON.issued_link(issued))
    end
  end

  operation(:revoke_link,
    summary: "Revoke a live activation link (vendors)",
    parameters: [@id],
    responses: [ok: {"Link", "application/json", S.activation_link()}]
  )

  def revoke_link(conn, %{id: id}) do
    with {:ok, link} <- BusinessActivation.revoke_link(conn.assigns.platform_context, id) do
      json(conn, BusinessAccountJSON.link(link))
    end
  end
end
