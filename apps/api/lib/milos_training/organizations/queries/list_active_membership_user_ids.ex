defmodule MilosTraining.Organizations.Queries.ListActiveMembershipUserIds do
  alias MilosTraining.Organizations.{OrganizationStore, TenantContext}

  def call(%TenantContext{organization_id: organization_id}),
    do: OrganizationStore.list_active_membership_user_ids(organization_id)

  def call(_context), do: []
end
