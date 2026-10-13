defmodule MilosTraining.Organizations.Queries.ListActiveInvitations do
  @moduledoc "Pending (unredeemed, unrevoked, unexpired) invitations of the current organization."

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.TenantAuthorization
  alias MilosTraining.Organizations.OrganizationStore

  def call(context, now) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]) do
      invitations =
        RepoContext.run(context, fn ->
          OrganizationStore.list_active_invitations(context.organization_id, now)
        end)

      {:ok, invitations}
    end
  end
end
