defmodule PaleeWeb.AdminFiscalEInvoicingController do
  @moduledoc """
  Staff › Fiscal › Peppol e-invoicing (ADR-250): the network connection,
  the state of every submission with its attempts, and sending a refused,
  failed or uncertain document again.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Fiscal.FiscalEInvoicing
  alias PaleeWeb.Schemas.Fiscal, as: F
  alias PaleeWeb.Schemas.FiscalCompliance, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Fiscal"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:connection,
    summary: "The Peppol connection (access point, environment, Peppol id; never the key)",
    responses: [ok: {"Connection", "application/json", C.peppol_connection_status()}]
  )

  def connection(conn, _params),
    do: json(conn, FiscalEInvoicing.connection(conn.assigns.tenant_context))

  operation(:save_connection,
    summary: "Connect to Peppol: sandbox, or Storecove (test or production)",
    description:
      "`test` and `production` send through Storecove and need the business's legal entity id " <>
        "and API key; a saved key is kept when none is sent. The Peppol id defaults to the " <>
        "`0208` enterprise number of the business. The webhook URL is shown once, when a new " <>
        "token is made. Documents waiting for a connection are sent right after.",
    request_body: F.body(C.peppol_connection_body()),
    responses: [ok: {"Connection", "application/json", F.one(:connection, C.peppol_connection())}]
  )

  def save_connection(conn, _params) do
    with {:ok, connection} <-
           FiscalEInvoicing.save_connection(conn.assigns.tenant_context, conn.body_params) do
      json(conn, %{connection: connection})
    end
  end

  operation(:index,
    summary: "Peppol submissions, newest first, with counts per status",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: C.einvoice_statuses()}
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
    responses: [ok: {"Submissions", "application/json", C.einvoice_page()}]
  )

  def index(conn, params),
    do: json(conn, FiscalEInvoicing.list(conn.assigns.tenant_context, params))

  operation(:show,
    summary: "A Peppol submission with its attempts",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: F.uuid()}],
    responses: [ok: {"Submission", "application/json", F.one(:submission, C.einvoice_detail())}]
  )

  def show(conn, %{id: id}) do
    with {:ok, submission} <- FiscalEInvoicing.get(conn.assigns.tenant_context, id) do
      json(conn, %{submission: submission})
    end
  end

  operation(:retry,
    summary: "Send a refused, failed or uncertain document over Peppol again",
    description:
      "An uncertain submission may already have reached the access point: check its portal " <>
        "first. It is sent with the same idempotency GUID, so a copy is refused, not delivered.",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: F.uuid()}],
    responses: [ok: {"Submission", "application/json", F.one(:submission, C.einvoice())}]
  )

  def retry(conn, %{id: id}) do
    with {:ok, submission} <- FiscalEInvoicing.retry(conn.assigns.tenant_context, id) do
      json(conn, %{submission: submission})
    end
  end
end
