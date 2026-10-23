defmodule Palee.Organizations.Domain.TenantDataPolicy do
  @moduledoc """
  Organizations tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "organizations",
            purge_order: 1000,
            disposition: :purge,
            basis:
              "Memberships and their branch scopes (ADR-186), invitations, settings, the public profile and its tag suggestions, retired slug aliases, provisioning events, members' remembered provider selections (ADR-162) and the platform plan subscription (ADR-170) are removed with the organization row; the platform purge record replaces them as the audit trail.",
            excluded_columns: ["token_digest", "intended_email_digest"],
            tables: [
              %{table: "profile_tag_suggestions"},
              %{table: "organization_public_profiles"},
              %{table: "registration_invitations"},
              %{table: "organization_domains"},
              %{table: "organization_slug_aliases"},
              %{table: "organization_settings"},
              %{table: "organization_provisioning_events"},
              %{table: "organization_platform_subscriptions"},
              %{table: "account_provider_selections", rls: :user},
              %{table: "membership_location_scopes"},
              %{table: "organization_memberships"}
            ]
          })

  def policy, do: @policy
end
