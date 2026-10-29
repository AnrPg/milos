defmodule Palee.Fiscal.Domain.TenantDataPolicy do
  @moduledoc """
  Fiscal tenant data retention and purge policy (ADR-117, ADR-240).

  Fiscal documents, the journal and closings are tax records: kept for the
  longest statutory minimum of any supported country (10 years), archived
  and only then purged. Purged before Finance, which later points at fiscal
  documents.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "fiscal",
            purge_order: 85,
            disposition: :retain,
            retain_years: 10,
            # ADR-243, ADR-250, ADR-251: provider credentials never leave the
            # database (myDATA key, Peppol access point key and webhook token
            # hash, fiskaly key, secret and TSE admin PIN).
            excluded_columns: [
              "subscription_key",
              "api_key",
              "api_secret",
              "admin_pin",
              "webhook_token_hash"
            ],
            basis:
              "Fiscal documents, their lines, their reports to the tax authority, their Peppol submissions and TSE/RKSV signatures, the inalterable journal and period closings are tax records (NF525, GoBD, Greek and Swiss record-keeping rules); they are archived and kept for 10 years, the longest minimum of any supported country.",
            tables: [
              %{table: "fiscal_till_signature_attempts"},
              %{table: "fiscal_till_signatures"},
              %{table: "fiscal_till_connections"},
              %{table: "fiscal_einvoice_attempts"},
              %{table: "fiscal_einvoice_submissions"},
              %{table: "fiscal_network_connections"},
              %{table: "fiscal_transmission_attempts"},
              %{table: "fiscal_transmissions"},
              %{table: "fiscal_authority_connections"},
              %{table: "fiscal_period_closings"},
              %{table: "fiscal_document_lines"},
              %{table: "fiscal_documents"},
              %{table: "fiscal_journal_entries"},
              %{table: "fiscal_journal_heads"},
              %{table: "fiscal_sequences"},
              %{table: "fiscal_business_identities"}
            ]
          })

  def policy, do: @policy
end
