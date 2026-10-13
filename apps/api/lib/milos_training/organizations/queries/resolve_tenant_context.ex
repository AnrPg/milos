defmodule MilosTraining.Organizations.Queries.ResolveTenantContext do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.TenantAuthorization
  alias MilosTraining.Organizations.OrganizationStore

  def call(account, slug, request_metadata) when is_map(account) and is_binary(slug) do
    # Resolution runs inside a user-scoped session so the root tenant tables'
    # RLS policies have an `app.user_id` to key on (F-16). Without this the
    # policies would be circular: reading `organizations` to build a context
    # would require a context.
    RepoContext.run(%{user_id: account.id}, fn ->
      # ADR-122: a retired slug resolves transparently to its organization, so
      # bookmarks, stored selections, stale token claims and socket params
      # keep working after a rename. The context always carries the canonical
      # organization; transports compare it with the requested slug to signal
      # the new one.
      organization =
        OrganizationStore.get_organization_by_slug(slug) ||
          OrganizationStore.get_organization_by_slug_alias(slug)

      membership =
        if organization do
          OrganizationStore.get_membership(organization.id, account.id)
        end

      TenantAuthorization.build(
        account,
        organization,
        membership,
        request_metadata,
        role_grants(organization)
      )
    end)
  end

  def call(_account, _slug, _request_metadata), do: {:error, :membership_required}

  # What the gym unlocked for roles such as front desk (ADR-099).
  defp role_grants(nil), do: %{}

  defp role_grants(organization) do
    case OrganizationStore.get_organization_settings(organization.id) do
      %{settings: %{"role_grants" => grants}} when is_map(grants) -> grants
      _none -> %{}
    end
  end
end
