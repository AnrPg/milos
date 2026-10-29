defmodule PaleeWeb.AdminFiscalController do
  @moduledoc """
  Staff › Fiscal (ADR-240–242): the business's legal identity, fiscal
  documents and credit notes, journal verification, closings and the signed
  audit archive.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Fiscal.FiscalAdmin
  alias PaleeWeb.Schemas.Fiscal, as: F

  action_fallback PaleeWeb.FallbackController

  tags(["Fiscal"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: F.uuid()}
  @date %Schema{type: :string, format: :date}

  operation(:countries,
    summary: "Supported countries, what each asks of a business, and the VAT schemes",
    responses: [ok: {"Countries", "application/json", F.countries()}]
  )

  def countries(conn, _params), do: json(conn, FiscalAdmin.countries())

  operation(:identity,
    summary: "The business's legal identity, its country profile and the fields still missing",
    responses: [ok: {"Identity", "application/json", F.identity_status()}]
  )

  def identity(conn, _params), do: json(conn, FiscalAdmin.identity(conn.assigns.tenant_context))

  operation(:save_identity,
    summary: "Save the business's legal identity (partial updates allowed)",
    description:
      "Tax ids are checked against their country's format and check digits; field errors " <>
        "come back as `validation_failed` with one code per field. Every change is journaled.",
    request_body: F.body(F.identity_body()),
    responses: [ok: {"Identity", "application/json", F.identity_status()}]
  )

  def save_identity(conn, _params) do
    with {:ok, status} <- FiscalAdmin.save_identity(conn.assigns.tenant_context, conn.body_params) do
      json(conn, status)
    end
  end

  operation(:documents,
    summary: "Fiscal documents, newest first",
    parameters: [
      %Parameter{
        name: :kind,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["receipt", "invoice", "credit_note"]}
      },
      %Parameter{name: :from, in: :query, required: false, schema: @date},
      %Parameter{name: :to, in: :query, required: false, schema: @date},
      %Parameter{
        name: :number,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 40}
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
    responses: [ok: {"Documents", "application/json", F.document_page()}]
  )

  def documents(conn, params),
    do: json(conn, FiscalAdmin.list_documents(conn.assigns.tenant_context, params))

  operation(:document,
    summary: "A fiscal document with its lines and the credit notes against it",
    parameters: [@id],
    responses: [ok: {"Document", "application/json", F.one(:document, F.document_detail())}]
  )

  def document(conn, %{id: id}) do
    with {:ok, document} <- FiscalAdmin.document(conn.assigns.tenant_context, id) do
      json(conn, %{document: document})
    end
  end

  operation(:credit,
    summary: "Issue a credit note for a document (all that is left, or chosen quantities)",
    description:
      "Documents are never changed: a credit note corrects them, with its reason (ADR-265). " <>
        "With `refund: true` the money goes back to the card the document was paid with and " <>
        "that refund issues the note (`document` is null when the refund could not issue it " <>
        "yet). Idempotent by `idempotency_key`.",
    parameters: [@id],
    request_body: F.body(F.credit_body()),
    responses: [
      created: {"Credit note", "application/json", F.credit_result()},
      ok: {"The credit note of an earlier identical request", "application/json", F.credit_result()}
    ]
  )

  def credit(conn, %{id: id}) do
    with {:ok, result, mode} <-
           FiscalAdmin.credit(conn.assigns.tenant_context, id, conn.body_params) do
      conn
      |> put_status(if(mode == :replayed, do: :ok, else: :created))
      |> json(result)
    end
  end

  operation(:verify_journal,
    summary: "Recompute the journal's hash chain and signatures",
    responses: [ok: {"Verification", "application/json", F.one(:verification, F.verification())}]
  )

  def verify_journal(conn, _params) do
    with {:ok, result} <- FiscalAdmin.verify_journal(conn.assigns.tenant_context) do
      json(conn, %{verification: result})
    end
  end

  operation(:closings,
    summary: "Daily, monthly and yearly closings",
    parameters: [
      %Parameter{
        name: :kind,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["day", "month", "year"]}
      },
      %Parameter{name: :from, in: :query, required: false, schema: @date},
      %Parameter{name: :to, in: :query, required: false, schema: @date},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 2000}
      }
    ],
    responses: [
      ok:
        {"Closings", "application/json",
         F.one(:closings, %Schema{type: :array, items: F.closing()})}
    ]
  )

  def closings(conn, params),
    do: json(conn, %{closings: FiscalAdmin.closings(conn.assigns.tenant_context, params)})

  operation(:archive,
    summary: "Download the signed audit archive of a date range (ZIP)",
    parameters: [
      %Parameter{name: :from, in: :query, required: true, schema: @date},
      %Parameter{name: :to, in: :query, required: true, schema: @date}
    ],
    responses: [ok: {"ZIP archive", "application/zip", %Schema{type: :string, format: :binary}}]
  )

  def archive(conn, params) do
    with {:ok, %{filename: filename, content: content}} <-
           FiscalAdmin.archive(conn.assigns.tenant_context, params) do
      send_download(conn, {:binary, content}, filename: filename, content_type: "application/zip")
    end
  end
end
