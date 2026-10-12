defmodule MilosTraining.Finance.Domain.TenantDataPolicy do
  @moduledoc """
  Finance tenant data retention and purge policy (ADR-107).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "finance",
            purge_order: 90,
            disposition: :retain,
            retain_years: 10,
            basis:
              "Invoices, payments, reversals, refund receipts, reconciliation records, accounting-export runs and the ledgers behind them are accounting records with a statutory retention period; they are archived with their uploaded documents and purged from the live database.",
            retained_object_prefixes: ["invoices/"],
            tables: [
              # ADR-116: refund receipts and reconciliation records reference
              # reversals and payments, so they are deleted first.
              %{table: "finance_reconciliation_records"},
              %{table: "finance_refund_receipts"},
              %{table: "finance_accounting_exports"},
              %{table: "finance_document_counters"},
              %{table: "finance_entitlement_usage_entries"},
              %{table: "finance_credit_ledger_entries"},
              %{table: "finance_payment_reversals"},
              %{table: "promotion_redemptions"},
              %{table: "referral_rewards"},
              %{table: "referral_events"},
              %{table: "referral_programs"},
              %{table: "promotion_codes"},
              %{table: "promotion_campaigns"},
              %{table: "finance_invoice_lines"},
              %{table: "membership_payments"},
              %{table: "finance_invoices"},
              %{table: "membership_package_subscriptions"},
              %{table: "membership_packages"},
              %{table: "memberships"},
              %{table: "finance_settings"}
            ]
          })

  def policy, do: @policy
end
