defmodule MilosTraining.Organizations.Queries.ListActiveMembershipUserIds do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationStore, TenantContext}

  # organization_memberships is a root tenant table, so the lookup runs inside
  # a tenant scope (TD-046): the acting user's for a request, or the
  # organization's own for server-side callers that pass a trusted id.
  def call(%TenantContext{organization_id: organization_id} = context) do
    RepoContext.run(context, fn ->
      OrganizationStore.list_active_membership_user_ids(organization_id)
    end)
  end

  def call(organization_id) when is_binary(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      OrganizationStore.list_active_membership_user_ids(organization_id)
    end)
  end

  def call(_context), do: []
end
