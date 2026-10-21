defmodule PaleeWeb.AdminFinanceAccountingController do
  @moduledoc """
  Staff endpoints for ADR-126: refund receipts, manual payment-provider
  reconciliation and accounting exports. Tenant-scoped through
  `conn.assigns.tenant_context`; the admin pipeline restricts them to
  organization owners and admins.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{
    GetFinanceAccountingExportDownload,
    GetFinanceReconciliationCandidates,
    GetFinanceRefundReceipt,
    ListFinanceAccountingExports,
    ListFinanceReconciliationRecords,
    ListFinanceRefundReceipts,
    MatchFinanceReconciliationRecord,
    RecordFinanceReconciliationLine,
    RenderFinanceRefundReceipt,
    RequestFinanceAccountingExport,
    UnmatchFinanceReconciliationRecord
  }

  alias PaleeWeb.Controllers.ReceiptDocumentResponse
  alias PaleeWeb.Schemas.FinanceAccounting
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Admin Finance Accounting"])
  security([%{"bearerAuth" => []}])

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    [json_render_error_v2: true]
    when action in [
           :record_reconciliation_line,
           :match_reconciliation,
           :unmatch_reconciliation,
           :request_export
         ]
  )

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @error {"Error", "application/json", %Schema{type: :object}}

  # --- Refund receipts ------------------------------------------------------

  operation(:refund_receipts,
    summary: "List the organization's refund receipts, newest number first",
    parameters: [
      %Parameter{name: :q, in: :query, schema: %Schema{type: :string}},
      %Parameter{name: :user_id, in: :query, schema: %Schema{type: :string, format: :uuid}},
      %Parameter{name: :from, in: :query, schema: %Schema{type: :string, format: :date}},
      %Parameter{name: :to, in: :query, schema: %Schema{type: :string, format: :date}},
      %Parameter{
        name: :limit,
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 500}
      }
    ],
    responses: [
      ok: {"Refund receipts", "application/json", FinanceAccounting.refund_receipt_collection()}
    ]
  )

  def refund_receipts(conn, params) do
    filters = Map.take(params, ["q", "user_id", "from", "to", "limit"])

    with {:ok, payload} <- ListFinanceRefundReceipts.call(tenant_context(conn), :staff, filters) do
      json(conn, payload)
    end
  end

  operation(:refund_receipt,
    summary: "Get one refund receipt with its immutable snapshot",
    parameters: [@id_param],
    responses: [
      ok: {"Refund receipt", "application/json", FinanceAccounting.refund_receipt_response()},
      not_found: @error
    ]
  )

  def refund_receipt(conn, %{"id" => id}) do
    with {:ok, receipt} <- GetFinanceRefundReceipt.call(tenant_context(conn), id, :staff) do
      json(conn, %{refund_receipt: receipt})
    end
  end

  operation(:refund_receipt_document,
    summary: "Printable HTML refund receipt",
    description:
      "Deterministic, self-contained HTML (no scripts or external resources) rendered from " <>
        "the immutable snapshot. Print or save as PDF from the browser.",
    parameters: [
      @id_param,
      %Parameter{name: :locale, in: :query, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"Receipt document", "text/html", %Schema{type: :string}},
      not_found: @error
    ]
  )

  def refund_receipt_document(conn, %{"id" => id} = params) do
    locale = ReceiptDocumentResponse.locale(conn, params)

    with {:ok, document} <-
           RenderFinanceRefundReceipt.call(tenant_context(conn), id, :staff, locale) do
      ReceiptDocumentResponse.send(conn, document)
    end
  end

  # --- Reconciliation -------------------------------------------------------

  operation(:reconciliation_records,
    summary: "List payment-provider reconciliation records",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        schema: %Schema{type: :string, enum: ["unmatched", "matched", "mismatched"]}
      },
      %Parameter{name: :provider, in: :query, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 500}
      }
    ],
    responses: [
      ok:
        {"Reconciliation records", "application/json",
         FinanceAccounting.reconciliation_collection()}
    ]
  )

  def reconciliation_records(conn, params) do
    filters = Map.take(params, ["status", "provider", "limit"])

    with {:ok, payload} <- ListFinanceReconciliationRecords.call(tenant_context(conn), filters) do
      json(conn, payload)
    end
  end

  operation(:record_reconciliation_line,
    summary: "Record an external provider statement line",
    description:
      "Idempotent on (organization, provider, external_reference): an identical replay " <>
        "returns the existing record with 200 and `idempotent_replay: true`; a replay with a " <>
        "different type, amount, currency or date returns 409 `reconciliation_reference_conflict`.",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: FinanceAccounting.reconciliation_line_request()}
      }
    },
    responses: [
      created:
        {"Recorded statement line", "application/json",
         FinanceAccounting.reconciliation_response()},
      ok:
        {"Replayed statement line", "application/json",
         FinanceAccounting.reconciliation_response()},
      conflict: @error,
      unprocessable_entity: @error
    ]
  )

  def record_reconciliation_line(conn, _params) do
    with {:ok, record, outcome} <-
           RecordFinanceReconciliationLine.call(
             tenant_context(conn),
             current_user_id(conn),
             conn.body_params
           ) do
      conn
      |> put_status(if(outcome == :created, do: :created, else: :ok))
      |> json(%{reconciliation_record: record, idempotent_replay: outcome == :replayed})
    end
  end

  operation(:reconciliation_candidates,
    summary: "Ranked internal payments or reversals that could match a statement line",
    parameters: [@id_param],
    responses: [
      ok:
        {"Match candidates", "application/json",
         FinanceAccounting.reconciliation_candidates_response()},
      not_found: @error
    ]
  )

  def reconciliation_candidates(conn, %{"id" => id}) do
    with {:ok, payload} <- GetFinanceReconciliationCandidates.call(tenant_context(conn), id) do
      json(conn, payload)
    end
  end

  operation(:match_reconciliation,
    summary: "Match a statement line to an internal payment or reversal",
    description:
      "The record becomes `matched`, or `mismatched` with the discrepancies found " <>
        "(amount, currency, date tolerance, settlement, type). An internal fact can be linked " <>
        "to one statement line only (409 `reconciliation_target_already_matched`).",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: FinanceAccounting.reconciliation_match_request()}
      }
    },
    responses: [
      ok: {"Matched record", "application/json", FinanceAccounting.reconciliation_response()},
      not_found: @error,
      conflict: @error,
      unprocessable_entity: @error
    ]
  )

  def match_reconciliation(conn, params) do
    with {:ok, record} <-
           MatchFinanceReconciliationRecord.call(
             tenant_context(conn),
             path_id(params),
             current_user_id(conn),
             conn.body_params
           ) do
      json(conn, %{reconciliation_record: record})
    end
  end

  operation(:unmatch_reconciliation,
    summary: "Clear a statement line's match",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: false,
      content: %{
        "application/json" => %MediaType{
          schema: FinanceAccounting.reconciliation_unmatch_request()
        }
      }
    },
    responses: [
      ok: {"Unmatched record", "application/json", FinanceAccounting.reconciliation_response()},
      not_found: @error
    ]
  )

  def unmatch_reconciliation(conn, params) do
    with {:ok, record} <-
           UnmatchFinanceReconciliationRecord.call(
             tenant_context(conn),
             path_id(params),
             current_user_id(conn),
             conn.body_params
           ) do
      json(conn, %{reconciliation_record: record})
    end
  end

  # --- Accounting exports ---------------------------------------------------

  operation(:exports,
    summary: "Accounting export run history",
    parameters: [
      %Parameter{
        name: :limit,
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 500}
      }
    ],
    responses: [
      ok:
        {"Accounting export runs", "application/json",
         FinanceAccounting.accounting_export_collection()}
    ]
  )

  def exports(conn, params) do
    with {:ok, payload} <-
           ListFinanceAccountingExports.call(tenant_context(conn), Map.take(params, ["limit"])) do
      json(conn, payload)
    end
  end

  operation(:request_export,
    summary: "Export payments, allocations, reversals, credits and refund receipts",
    description:
      "Ranges up to 31 days are built immediately (201, status `completed`); longer ranges " <>
        "are queued for background processing (202, status `queued`). The ZIP holds one CSV " <>
        "and one JSON file per dataset plus a checksummed manifest (schema_version 1).",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: FinanceAccounting.accounting_export_request()}
      }
    },
    responses: [
      created:
        {"Completed export", "application/json", FinanceAccounting.accounting_export_response()},
      accepted:
        {"Queued export", "application/json", FinanceAccounting.accounting_export_response()},
      unprocessable_entity: @error,
      service_unavailable: @error
    ]
  )

  def request_export(conn, _params) do
    with {:ok, export} <-
           RequestFinanceAccountingExport.call(
             tenant_context(conn),
             current_user_id(conn),
             conn.body_params
           ) do
      conn
      |> put_status(if(export.status == "completed", do: :created, else: :accepted))
      |> json(%{accounting_export: export})
    end
  end

  operation(:export_download,
    summary: "Short-lived signed download link for a completed accounting export",
    parameters: [@id_param],
    responses: [
      ok: {"Download link", "application/json", FinanceAccounting.accounting_export_download()},
      not_found: @error,
      conflict: @error
    ]
  )

  def export_download(conn, %{"id" => id}) do
    with {:ok, payload} <- GetFinanceAccountingExportDownload.call(tenant_context(conn), id) do
      json(conn, payload)
    end
  end

  defp path_id(params), do: params[:id] || params["id"]
  defp tenant_context(conn), do: conn.assigns[:tenant_context]

  defp current_user_id(conn) do
    case Guardian.Plug.current_resource(conn) do
      %{id: id} -> id
      _ -> nil
    end
  end
end
