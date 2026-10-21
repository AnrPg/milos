defmodule Palee.Organizations.Queries.ListMemberships do
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.OrganizationStore

  def call(%{id: user_id}), do: call(user_id)

  def call(user_id) when is_binary(user_id) do
    RepoContext.run(%{user_id: user_id}, fn -> OrganizationStore.list_memberships(user_id) end)
  end
end
