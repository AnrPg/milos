defmodule Palee.Organizations.Queries.ListActiveInvitations do
  @moduledoc "Pending (unredeemed, unrevoked, unexpired) invitations of the current organization."

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.TenantAuthorization
  alias Palee.Organizations.OrganizationStore

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
