defmodule Palee.Documents.Domain.TenantDataPolicy do
  @moduledoc """
  Documents tenant data retention and purge policy (ADR-117, ADR-252).

  Signed documents and their evidence are what the box relies on in a
  dispute, so the signatures, the versions they point at, the requests and
  the audit log are archived and kept for 5 years (the general limitation
  period for claims in tort in Greece, art. 937 Civil Code). The evidence
  PDFs stay under `documents/evidence/`.

  Health certificates are special-category data (GDPR art. 9) with no
  reason to outlive the business: they are purged, not archived.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "documents",
            purge_order: 83,
            disposition: :retain,
            retain_years: 5,
            basis:
              "Signed documents (waivers, terms, privacy notices, health declarations), their versions, the signature evidence and its audit log are the box's proof in a dispute; they are archived and kept for 5 years (limitation of claims). Health certificates are special-category data and are purged, never archived.",
            tables: [
              %{table: "health_certificates"},
              %{table: "document_audit_events"},
              %{table: "document_signature_requests"},
              %{table: "document_signatures"},
              %{table: "document_versions"},
              %{table: "document_templates"},
              %{table: "document_settings"}
            ],
            retained_tables: [
              "document_audit_events",
              "document_signature_requests",
              "document_signatures",
              "document_versions",
              "document_templates"
            ],
            retained_object_prefixes: ["documents/evidence/"]
          })

  def policy, do: @policy
end
