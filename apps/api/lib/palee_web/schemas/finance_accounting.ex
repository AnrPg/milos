defmodule PaleeWeb.Schemas.FinanceAccounting do
  @moduledoc """
  OpenAPI schemas for ADR-126 refund receipts, payment-provider
  reconciliation records and accounting exports.
  """

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @date %Schema{type: :string, format: :date}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @nullable_string %Schema{type: :string, nullable: true}

  @reversal_types ["refund", "payment_reversal", "waiver_reversal"]
  @discrepancies [
    "type_mismatch",
    "amount_mismatch",
    "currency_mismatch",
    "date_out_of_tolerance",
    "provider_not_settled",
    "internal_not_settled"
  ]

  @receipt_properties %{
    id: @uuid,
    organization_id: @uuid,
    receipt_number: %Schema{
      type: :string,
      description: "Gapless per-organization number, e.g. RFD-000001"
    },
    sequence: %Schema{type: :integer, minimum: 1},
    finance_payment_reversal_id: @uuid,
    membership_payment_id: @uuid,
    finance_invoice_id: @nullable_uuid,
    membership_id: @uuid,
    user_id: @uuid,
    reversal_type: %Schema{type: :string, enum: @reversal_types},
    amount_cents: %Schema{type: :integer, minimum: 1},
    currency: %Schema{type: :string},
    reason: @nullable_string,
    issued_by_id: @nullable_uuid,
    reversal_occurred_at: @datetime,
    issued_at: @datetime,
    invoice_number: @nullable_string,
    member_display_name: @nullable_string,
    schema_version: %Schema{type: :integer},
    snapshot_sha256: %Schema{type: :string, description: "SHA-256 of the canonical snapshot"},
    integrity_verified: %Schema{
      type: :boolean,
      description: "True when the stored snapshot still hashes to snapshot_sha256"
    }
  }

  @receipt_required [
    :id,
    :receipt_number,
    :sequence,
    :finance_payment_reversal_id,
    :membership_payment_id,
    :user_id,
    :reversal_type,
    :amount_cents,
    :currency,
    :issued_at,
    :snapshot_sha256,
    :integrity_verified
  ]

  def refund_receipt do
    %Schema{
      title: "FinanceRefundReceipt",
      type: :object,
      required: @receipt_required,
      properties: @receipt_properties
    }
  end

  def refund_receipt_detail do
    %Schema{
      title: "FinanceRefundReceiptDetail",
      type: :object,
      required: [:snapshot | @receipt_required],
      properties:
        Map.put(@receipt_properties, :snapshot, %Schema{
          type: :object,
          additionalProperties: true,
          description: "Immutable receipt snapshot captured at issue time (schema_version 1)"
        })
    }
  end

  def refund_receipt_collection do
    %Schema{
      title: "FinanceRefundReceiptCollection",
      type: :object,
      required: [:refund_receipts],
      properties: %{
        refund_receipts: %Schema{type: :array, items: refund_receipt()},
        branch_filter: PaleeWeb.Schemas.LocationScope.filter_schema()
      }
    }
  end

  def refund_receipt_response do
    %Schema{
      title: "FinanceRefundReceiptResponse",
      type: :object,
      required: [:refund_receipt],
      properties: %{refund_receipt: refund_receipt_detail()}
    }
  end

  def reconciliation_record do
    %Schema{
      title: "FinanceReconciliationRecord",
      type: :object,
      required: [
        :id,
        :provider,
        :external_reference,
        :external_type,
        :external_status,
        :statement_amount_cents,
        :statement_currency,
        :statement_occurred_on,
        :status,
        :discrepancies
      ],
      properties: %{
        id: @uuid,
        organization_id: @uuid,
        provider: %Schema{type: :string},
        external_reference: %Schema{type: :string},
        external_type: %Schema{type: :string, enum: ["payment", "refund"]},
        external_status: %Schema{type: :string, enum: ["settled", "pending", "failed"]},
        statement_amount_cents: %Schema{type: :integer, minimum: 1},
        statement_currency: %Schema{type: :string},
        statement_occurred_on: @date,
        statement_description: @nullable_string,
        status: %Schema{type: :string, enum: ["unmatched", "matched", "mismatched"]},
        target_type: %Schema{type: :string, enum: ["payment", "reversal"], nullable: true},
        membership_payment_id: @nullable_uuid,
        finance_payment_reversal_id: @nullable_uuid,
        discrepancies: %Schema{type: :array, items: %Schema{type: :string, enum: @discrepancies}},
        discrepancy_notes: @nullable_string,
        matched_at: @nullable_datetime,
        matched_by_id: @nullable_uuid,
        recorded_by_id: @nullable_uuid,
        inserted_at: @datetime,
        updated_at: @datetime
      }
    }
  end

  def reconciliation_collection do
    %Schema{
      title: "FinanceReconciliationRecordCollection",
      type: :object,
      required: [:reconciliation_records],
      properties: %{reconciliation_records: %Schema{type: :array, items: reconciliation_record()}}
    }
  end

  def reconciliation_response do
    %Schema{
      title: "FinanceReconciliationRecordResponse",
      type: :object,
      required: [:reconciliation_record],
      properties: %{
        reconciliation_record: reconciliation_record(),
        idempotent_replay: %Schema{type: :boolean}
      }
    }
  end

  def reconciliation_line_request do
    %Schema{
      title: "FinanceReconciliationLineRequest",
      type: :object,
      required: [
        :provider,
        :external_reference,
        :external_type,
        :statement_amount_cents,
        :statement_occurred_on
      ],
      properties: %{
        provider: %Schema{
          type: :string,
          minLength: 1,
          maxLength: 40,
          description: "Provider key, e.g. stripe, viva_wallet, bank_transfer"
        },
        external_reference: %Schema{type: :string, minLength: 1, maxLength: 120},
        external_type: %Schema{type: :string, enum: ["payment", "refund"]},
        external_status: %Schema{type: :string, enum: ["settled", "pending", "failed"]},
        statement_amount_cents: %Schema{type: :integer, minimum: 1},
        statement_currency: %Schema{type: :string, minLength: 3, maxLength: 3},
        statement_occurred_on: @date,
        statement_description: %Schema{type: :string, maxLength: 500, nullable: true}
      }
    }
  end

  def reconciliation_match_request do
    %Schema{
      title: "FinanceReconciliationMatchRequest",
      type: :object,
      required: [:target_type, :target_id],
      properties: %{
        target_type: %Schema{type: :string, enum: ["payment", "reversal"]},
        target_id: @uuid,
        notes: %Schema{type: :string, maxLength: 1000, nullable: true}
      }
    }
  end

  def reconciliation_unmatch_request do
    %Schema{
      title: "FinanceReconciliationUnmatchRequest",
      type: :object,
      properties: %{notes: %Schema{type: :string, maxLength: 1000, nullable: true}}
    }
  end

  def reconciliation_candidates_response do
    %Schema{
      title: "FinanceReconciliationCandidates",
      type: :object,
      required: [:reconciliation_record, :candidates],
      properties: %{
        reconciliation_record: reconciliation_record(),
        candidates: %Schema{
          type: :array,
          items: %Schema{
            title: "FinanceReconciliationCandidate",
            type: :object,
            required: [
              :target_type,
              :target_id,
              :amount_cents,
              :currency,
              :occurred_on,
              :evaluation
            ],
            properties: %{
              target_type: %Schema{type: :string, enum: ["payment", "reversal"]},
              target_id: @uuid,
              amount_cents: %Schema{type: :integer},
              currency: %Schema{type: :string},
              occurred_on: @date,
              status: @nullable_string,
              payment_method: @nullable_string,
              invoice_number: @nullable_string,
              member_user_id: @nullable_uuid,
              member_name: @nullable_string,
              evaluation: %Schema{
                type: :object,
                required: [:status, :discrepancies],
                properties: %{
                  status: %Schema{type: :string, enum: ["matched", "mismatched"]},
                  discrepancies: %Schema{
                    type: :array,
                    items: %Schema{type: :string, enum: @discrepancies}
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  def accounting_export do
    %Schema{
      title: "FinanceAccountingExport",
      type: :object,
      required: [
        :id,
        :range_start,
        :range_end,
        :status,
        :execution_mode,
        :schema_version,
        :row_counts,
        :files
      ],
      properties: %{
        id: @uuid,
        organization_id: @uuid,
        requested_by_id: @nullable_uuid,
        range_start: @date,
        range_end: @date,
        status: %Schema{type: :string, enum: ["queued", "running", "completed", "failed"]},
        execution_mode: %Schema{type: :string, enum: ["inline", "background"]},
        schema_version: %Schema{type: :integer},
        object_key: @nullable_string,
        byte_size: %Schema{type: :integer, nullable: true},
        sha256: %Schema{type: :string, nullable: true, description: "SHA-256 of the stored ZIP"},
        row_counts: %Schema{type: :object, additionalProperties: %Schema{type: :integer}},
        files: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:name, :sha256, :byte_size, :rows],
            properties: %{
              name: %Schema{type: :string},
              sha256: %Schema{type: :string},
              byte_size: %Schema{type: :integer},
              rows: %Schema{type: :integer}
            }
          }
        },
        error_reason: @nullable_string,
        started_at: @nullable_datetime,
        completed_at: @nullable_datetime,
        inserted_at: @datetime,
        updated_at: @datetime
      }
    }
  end

  def accounting_export_collection do
    %Schema{
      title: "FinanceAccountingExportCollection",
      type: :object,
      required: [:accounting_exports],
      properties: %{accounting_exports: %Schema{type: :array, items: accounting_export()}}
    }
  end

  def accounting_export_response do
    %Schema{
      title: "FinanceAccountingExportResponse",
      type: :object,
      required: [:accounting_export],
      properties: %{accounting_export: accounting_export()}
    }
  end

  def accounting_export_request do
    %Schema{
      title: "FinanceAccountingExportRequest",
      type: :object,
      required: [:range_start, :range_end],
      properties: %{range_start: @date, range_end: @date}
    }
  end

  def accounting_export_download do
    %Schema{
      title: "FinanceAccountingExportDownload",
      type: :object,
      required: [:download_url, :file_name, :expires_in_seconds],
      properties: %{
        download_url: %Schema{type: :string},
        file_name: %Schema{type: :string},
        sha256: @nullable_string,
        byte_size: %Schema{type: :integer, nullable: true},
        expires_in_seconds: %Schema{type: :integer}
      }
    }
  end
end
