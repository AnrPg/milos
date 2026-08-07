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
      organization = OrganizationStore.get_organization_by_slug(slug)

      membership =
        if organization do
          OrganizationStore.get_membership(organization.id, account.id)
        end

      TenantAuthorization.build(account, organization, membership, request_metadata)
    end)
  end

  def call(_account, _slug, _request_metadata), do: {:error, :membership_required}
end
