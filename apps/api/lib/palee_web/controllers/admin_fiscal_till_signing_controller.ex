defmodule PaleeWeb.AdminFiscalTillSigningController do
  @moduledoc """
  Staff › Fiscal › cash-register security (ADR-251): the TSE (Germany) or
  RKSV (Austria) connection, the signature of every receipt with what it
  prints, retrying a signature and an RKSV null receipt.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Fiscal.FiscalTillSigning
  alias PaleeWeb.Schemas.Fiscal, as: F
  alias PaleeWeb.Schemas.FiscalCompliance, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Fiscal"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @device %Parameter{
    name: :device,
    in: :path,
    required: true,
    schema: %Schema{type: :string, enum: ["tse", "rksv"]}
  }

  operation(:connection,
    summary: "The TSE or RKSV connection (provider, environment, unit; never the credentials)",
    parameters: [@device],
    responses: [ok: {"Connection", "application/json", C.till_connection_status()}]
  )

  def connection(conn, %{device: device}),
    do: json(conn, FiscalTillSigning.connection(conn.assigns.tenant_context, device))

  operation(:save_connection,
    summary: "Connect the till to a TSE (DE) or RKSV unit (AT): sandbox or fiskaly",
    description:
      "`test` and `production` use fiskaly SIGN DE / SIGN AT and need the API key and secret; " <>
        "saved ones are kept when none are sent. A new connection (or `reprovision`) creates and " <>
        "initialises the TSS and client, or the signature unit and cash register. Receipts " <>
        "waiting for a connection are signed right after.",
    parameters: [@device],
    request_body: F.body(C.till_connection_body()),
    responses: [ok: {"Connection", "application/json", F.one(:connection, C.till_connection())}]
  )

  def save_connection(conn, %{device: device}) do
    with {:ok, connection} <-
           FiscalTillSigning.save_connection(
             conn.assigns.tenant_context,
             device,
             conn.body_params
           ) do
      json(conn, %{connection: connection})
    end
  end

  operation(:index,
    summary: "Receipt signatures, newest first, with counts per status",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: C.signature_statuses()}
      },
      %Parameter{
        name: :device,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["tse", "rksv"]}
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
    responses: [ok: {"Signatures", "application/json", C.till_signature_page()}]
  )

  def index(conn, params),
    do: json(conn, FiscalTillSigning.list(conn.assigns.tenant_context, params))

  operation(:show,
    summary: "A receipt signature with what it prints and its attempts",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: F.uuid()}],
    responses: [
      ok: {"Signature", "application/json", F.one(:signature, C.till_signature_detail())}
    ]
  )

  def show(conn, %{id: id}) do
    with {:ok, signature} <- FiscalTillSigning.get(conn.assigns.tenant_context, id) do
      json(conn, %{signature: signature})
    end
  end

  operation(:retry,
    summary: "Sign a refused, failed or uncertain receipt again",
    description:
      "An uncertain signature is read back from the device first. A German receipt recorded " <>
        "as a TSE failure stays so.",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: F.uuid()}],
    responses: [ok: {"Signature", "application/json", F.one(:signature, C.till_signature())}]
  )

  def retry(conn, %{id: id}) do
    with {:ok, signature} <- FiscalTillSigning.retry(conn.assigns.tenant_context, id) do
      json(conn, %{signature: signature})
    end
  end

  operation(:null_receipt,
    summary: "Sign an RKSV null receipt (Nullbeleg)",
    responses: [
      created: {"Signature", "application/json", F.one(:signature, C.till_signature())}
    ]
  )

  def null_receipt(conn, _params) do
    with {:ok, signature} <- FiscalTillSigning.null_receipt(conn.assigns.tenant_context) do
      conn |> put_status(:created) |> json(%{signature: signature})
    end
  end
end
