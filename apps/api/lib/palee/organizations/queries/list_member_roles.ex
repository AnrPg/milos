defmodule Palee.Organizations.Queries.ListMemberRoles do
  @moduledoc """
  Role facts (primary role, role set, coach scope, notes visibility) of the
  active members of one organization, optionally narrowed by role set and/or
  one user (TD-092).

  Runs inside that organization's repo scope, like `ListStaffUserIds`, so the
  lookup resolves for coaches, front desk and jobs whose own RLS view of
  organization_memberships is limited to their row. The organization id always
  comes from server-side ownership, never from client input.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.OrganizationStore

  def call(organization_id, opts \\ [])

  def call(organization_id, opts) when is_binary(organization_id) do
    roles = opts |> Keyword.get(:roles) |> role_names()

    RepoContext.run(%{organization_id: organization_id}, fn ->
      OrganizationStore.list_member_roles(organization_id, roles, Keyword.get(opts, :user_id))
    end)
  end

  def call(_organization_id, _opts), do: []

  defp role_names(nil), do: nil
  defp role_names(roles), do: Enum.map(roles, &to_string/1)
end
