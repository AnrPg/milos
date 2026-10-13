defmodule MilosTraining.Organizations.Queries.ListStaffUserIds do
  @moduledoc """
  Active owner/admin/coach user ids of one organization, for staff fanout.

  Runs inside that organization's repo scope so the
  `milos_organization_staff_user_ids/1` function admits the lookup even when
  the caller holds no session of its own (application services after a write,
  Oban jobs). The organization id always comes from server-side ownership
  (tenant context or entity provenance), never from client input (TD-046).
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.OrganizationStore

  def call(organization_id) when is_binary(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      OrganizationStore.list_staff_user_ids(organization_id)
    end)
  end

  def call(_organization_id), do: []
end
