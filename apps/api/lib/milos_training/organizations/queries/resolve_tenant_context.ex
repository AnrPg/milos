defmodule MilosTraining.Organizations.Queries.ResolveTenantContext do
  alias MilosTraining.Organizations.Domain.TenantAuthorization
  alias MilosTraining.Organizations.OrganizationStore

  def call(account, slug, request_metadata) when is_map(account) and is_binary(slug) do
    organization = OrganizationStore.get_organization_by_slug(slug)

    membership =
      if organization do
        OrganizationStore.get_membership(organization.id, account.id)
      end

    TenantAuthorization.build(account, organization, membership, request_metadata)
  end

  def call(_account, _slug, _request_metadata), do: {:error, :membership_required}
end
