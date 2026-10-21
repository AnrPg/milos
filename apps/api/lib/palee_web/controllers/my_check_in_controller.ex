defmodule PaleeWeb.MyCheckInController do
  @moduledoc """
  Box › Check-in (ADR-155): the member's personal QR for this box and «Πρόσθεσε
  στο Wallet».
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{DeskCheckIn, MemberCodes, WalletPasses}
  alias PaleeWeb.Schemas.CheckIn, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Check-in"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:code,
    summary: "My personal check-in QR at this box (rotating every 30 s, or static per the box)",
    responses: [ok: {"Code", "application/json", S.member_code_response()}]
  )

  def code(conn, _params) do
    with {:ok, code} <- DeskCheckIn.member_code(conn.assigns.tenant_context),
         do: json(conn, code)
  end

  operation(:reset_code,
    summary: "Reset my static personal code: the old one and its Wallet cards stop",
    responses: [
      ok: {"The new code", "application/json", S.member_code_response()},
      conflict:
        {"The box uses rotating codes (member_code_not_static)", "application/json", S.error()}
    ]
  )

  def reset_code(conn, _params) do
    with {:ok, code} <- MemberCodes.reset(conn.assigns.tenant_context),
         do: json(conn, code)
  end

  operation(:add_wallet_pass,
    summary: "Add my check-in card at this box to Apple or Google Wallet",
    request_body: S.body(S.wallet_add_request()),
    responses: [
      ok: {"The card and how to add it", "application/json", S.wallet_add_response()},
      conflict:
        {"The box uses rotating codes, so no Wallet (wallet_requires_static_code)",
         "application/json", S.error()},
      service_unavailable:
        {"Wallet isn't configured on this server (wallet_not_configured)", "application/json",
         S.error()}
    ]
  )

  def add_wallet_pass(conn, _params) do
    with {:ok, result} <-
           WalletPasses.add(conn.assigns.tenant_context, conn.body_params.platform),
         do: json(conn, result)
  end
end
