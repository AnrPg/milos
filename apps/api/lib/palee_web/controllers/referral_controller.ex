defmodule PaleeWeb.ReferralController do
  @moduledoc """
  «Φέρε φίλο» (ADR-156, P2-M8): the invite page anyone can open, the friend's
  claim once signed in, and the member's own invites at a box.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Referrals
  alias PaleeWeb.Schemas.Referrals, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Referrals"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @not_found [
    not_found: {"No live invite with this code", "application/json", %Schema{type: :object}}
  ]

  operation(:invite,
    summary: "What an invite link shows: the box, who invites and the friend's gift (no sign-in)",
    parameters: [
      %Parameter{
        name: :code,
        in: :path,
        required: true,
        schema: %Schema{type: :string, maxLength: 32}
      }
    ],
    responses: [ok: {"Invite", "application/json", S.public_invite()}] ++ @not_found
  )

  def invite(conn, %{code: code}) do
    with {:ok, invite} <- Referrals.invite(code), do: json(conn, %{invite: invite})
  end

  operation(:claim,
    summary:
      "Records that the signed-in person came through a member's invite (first invite wins)",
    security: [%{"bearerAuth" => []}],
    request_body: S.body(S.claim_request()),
    responses: [ok: {"Claim", "application/json", S.claim_response()}] ++ @not_found
  )

  def claim(conn, _params) do
    params = conn.body_params

    with {:ok, result} <-
           Referrals.claim(conn.assigns.user_context.account, params.code, %{
             channel: Map.get(params, :channel),
             event_id: Map.get(params, :event_id),
             new_account: Map.get(params, :new_account, false)
           }),
         do: json(conn, result)
  end

  operation(:mine,
    summary: "Your «Φέρε φίλο» at the box: link, programme, events to invite to and your invites",
    security: [%{"bearerAuth" => []}],
    responses: [ok: {"Overview", "application/json", S.overview()}]
  )

  def mine(conn, _params) do
    with {:ok, overview} <- Referrals.overview(conn.assigns.tenant_context),
         do: json(conn, overview)
  end

  operation(:rotate_code,
    summary: "A new invite link at the box; the old one stops working",
    security: [%{"bearerAuth" => []}],
    responses: [ok: {"Code", "application/json", S.code_response()}]
  )

  def rotate_code(conn, _params) do
    with {:ok, code} <- Referrals.rotate_code(conn.assigns.tenant_context), do: json(conn, code)
  end
end
