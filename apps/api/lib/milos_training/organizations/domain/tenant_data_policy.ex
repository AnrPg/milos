defmodule MilosTraining.Organizations.Domain.TenantDataPolicy do
  @moduledoc """
  Organizations tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "organizations",
            purge_order: 1000,
            disposition: :purge,
            basis:
              "Memberships, invitations, settings, retired slug aliases and provisioning events are removed with the organization row; the platform purge record replaces them as the audit trail.",
            excluded_columns: ["token_digest", "intended_email_digest"],
            tables: [
              %{table: "registration_invitations"},
              %{table: "organization_domains"},
              %{table: "organization_slug_aliases"},
              %{table: "organization_settings"},
              %{table: "organization_provisioning_events"},
              %{table: "organization_memberships"}
            ]
          })

  def policy, do: @policy
end
