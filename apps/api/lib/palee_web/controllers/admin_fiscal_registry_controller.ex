defmodule PaleeWeb.AdminFiscalRegistryController do
  @moduledoc """
  Staff › billing details › «Συμπλήρωση από το ΑΦΜ» (ADR-265): the
  business's AADE registry connection and the look-up of a Greek business
  by ΑΦΜ. Look-ups are rate limited per staff member, on top of AADE's own
  quota.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.Fiscal.FiscalRegistry
  alias PaleeWeb.Schemas.Fiscal, as: F
  alias PaleeWeb.Schemas.FiscalRegistry, as: R

  action_fallback PaleeWeb.FallbackController

  tags(["Fiscal"])
  security([%{"bearerAuth" => []}])

  plug PaleeWeb.Plugs.RateLimit,
       [max: 30, interval: 60_000, bucket: "fiscal-registry"] when action == :lookup

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:connection,
    summary: "The AADE registry connection (environment and user; never the password)",
    responses: [ok: {"Connection", "application/json", R.connection_status()}]
  )

  def connection(conn, _params),
    do: json(conn, FiscalRegistry.connection(conn.assigns.tenant_context))

  operation(:save_connection,
    summary: "Connect AADE's registry service (RgWsPublic2) with the business's credentials",
    description:
      "`production` needs the special credentials AADE issued to the business for this " <>
        "service; a saved password is kept when none is sent. `sandbox` answers with made-up " <>
        "details and needs none.",
    request_body: F.body(R.connection_body()),
    responses: [ok: {"Connection", "application/json", R.connection_status()}]
  )

  def save_connection(conn, _params) do
    with {:ok, result} <-
           FiscalRegistry.save_connection(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:lookup,
    summary: "A Greek business's registry details by ΑΦΜ (AADE)",
    description:
      "The ΑΦΜ's check digit is verified first (`invalid_tax_id`). Errors: " <>
        "`registry_not_connected`, `registry_credentials_rejected`, `registry_not_found`, " <>
        "`registry_limit_reached`, `registry_unavailable`.",
    parameters: [
      tax_id: [
        in: :path,
        type: %Schema{type: :string, maxLength: 20},
        required: true,
        description: "The ΑΦΜ (9 digits)"
      ]
    ],
    responses: [ok: {"Business", "application/json", R.business()}]
  )

  def lookup(conn, %{tax_id: tax_id}) do
    with {:ok, result} <- FiscalRegistry.lookup(conn.assigns.tenant_context, tax_id) do
      json(conn, result)
    end
  end
end
