defmodule PaleeWeb.AdminFiscalReportingController do
  @moduledoc """
  Staff › Fiscal › reporting to the tax authority (ADR-243): the myDATA
  connection, the state of every report and retrying a refused one.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Fiscal.FiscalReporting
  alias PaleeWeb.Schemas.Fiscal, as: F
  alias PaleeWeb.Schemas.FiscalConnections, as: FC

  action_fallback PaleeWeb.FallbackController

  tags(["Fiscal"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:connection,
    summary: "The myDATA connection (environment and user; never the key)",
    responses: [ok: {"Connection", "application/json", F.connection_status()}]
  )

  def connection(conn, _params),
    do: json(conn, FiscalReporting.connection(conn.assigns.tenant_context))

  operation(:save_connection,
    summary:
      "Connect to myDATA: sandbox, AADE test or production with the business's credentials",
    description:
      "`test` and `production` need the business's myDATA user and subscription key; a saved " <>
        "key is kept when none is sent. The connection is then checked with AADE (ADR-273, " <>
        "`check`). Documents waiting for a connection are sent right after. Refused with " <>
        "`fiscal_connections_managed_by_palee` while the Palee team manages the connections.",
    request_body: F.body(F.connection_body()),
    responses: [ok: {"Connection", "application/json", FC.result(F.connection())}]
  )

  def save_connection(conn, _params) do
    with {:ok, result} <-
           FiscalReporting.save_connection(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:transmissions,
    summary: "Reports to the tax authority, newest first, with counts per status",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{
          type: :string,
          enum: ["pending", "sending", "accepted", "rejected", "failed"]
        }
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 200}
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      }
    ],
    responses: [ok: {"Transmissions", "application/json", F.transmission_page()}]
  )

  def transmissions(conn, params),
    do: json(conn, FiscalReporting.list(conn.assigns.tenant_context, params))

  operation(:retry,
    summary: "Send a refused or failed document to the tax authority again",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: F.uuid()}],
    responses: [
      ok: {"Transmission", "application/json", F.one(:transmission, F.transmission())}
    ]
  )

  def retry(conn, %{id: id}) do
    with {:ok, transmission} <- FiscalReporting.retry(conn.assigns.tenant_context, id) do
      json(conn, %{transmission: transmission})
    end
  end
end
