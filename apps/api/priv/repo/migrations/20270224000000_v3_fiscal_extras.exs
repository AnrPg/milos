defmodule Palee.Repo.Migrations.V3FiscalExtras do
  @moduledoc """
  ADR-265: three additions to the fiscal core.

    * `fiscal_documents.credit_reason` – why a credit note was issued
      (`product_return`, `billing_error`, `subscription_cancelled`,
      `other`). Set only when the note is inserted: the table stays
      insert-only (ADR-241), and the reason is part of the document's
      content hash and of its journal entry.
    * `payment_refunds.fiscal_credit` – what the credit note of a refund
      started from the credit-note panel must hold (reason and, for a
      partial note, the lines). The refund still issues the note
      (ADR-262), so one action never makes two notes.
    * `fiscal_authority_connections` also holds the business's
      credentials for AADE's registry service (`gr_registry`,
      RgWsPublic2), encrypted like the myDATA key.
  """

  use Ecto.Migration

  def up do
    alter table(:fiscal_documents) do
      add :credit_reason, :string
    end

    create constraint(:fiscal_documents, :fiscal_documents_credit_reason_check,
             check: """
             credit_reason IS NULL OR (kind = 'credit_note' AND credit_reason IN
               ('product_return', 'billing_error', 'subscription_cancelled', 'other'))
             """
           )

    alter table(:payment_refunds) do
      add :fiscal_credit, :map
    end

    drop constraint(:fiscal_authority_connections, :fiscal_authority_connections_check)

    create constraint(:fiscal_authority_connections, :fiscal_authority_connections_check,
             check: """
             ((authority = 'mydata' AND environment IN ('sandbox', 'test', 'production'))
               OR (authority = 'gr_registry' AND environment IN ('sandbox', 'production')))
             AND status IN ('active', 'invalid')
             AND (environment = 'sandbox' OR (user_id IS NOT NULL AND subscription_key IS NOT NULL))
             """
           )
  end

  def down do
    execute("DELETE FROM fiscal_authority_connections WHERE authority = 'gr_registry'")
    drop constraint(:fiscal_authority_connections, :fiscal_authority_connections_check)

    create constraint(:fiscal_authority_connections, :fiscal_authority_connections_check,
             check: """
             authority IN ('mydata') AND environment IN ('sandbox', 'test', 'production')
             AND status IN ('active', 'invalid')
             AND (environment = 'sandbox' OR (user_id IS NOT NULL AND subscription_key IS NOT NULL))
             """
           )

    alter table(:payment_refunds) do
      remove :fiscal_credit
    end

    drop constraint(:fiscal_documents, :fiscal_documents_credit_reason_check)

    alter table(:fiscal_documents) do
      remove :credit_reason
    end
  end
end
