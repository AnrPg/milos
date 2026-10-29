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
            basis:
              "Fiscal documents, their lines, their reports to the tax authority, the inalterable journal and period closings are tax records (NF525, GoBD, Greek and Swiss record-keeping rules); they are archived and kept for 10 years, the longest minimum of any supported country.",
            tables: [
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
