defmodule Palee.Application.ListOrganizationMemberships do
  @moduledoc """
  The account's memberships for the session payload, each with the branches
  the person works at as staff (ADR-186), so the capabilities it carries are
  the narrowed ones the API enforces.
  """

  alias Palee.Organizations

  def call(%{id: user_id}) do
    {:ok,
     user_id
     |> Organizations.list_memberships()
     # ADR-185: a person's own organiser organisation is not one of their gyms.
     |> Organizations.provider_memberships()
     |> Enum.map(&with_location_scope(&1, user_id))}
  end

  defp with_location_scope(%{membership: membership} = entry, user_id) do
    scopes =
      Organizations.membership_location_scopes(
        %{organization_id: membership.organization_id, user_id: user_id},
        [membership]
      )

    Map.put(entry, :location_scope, Map.get(scopes, membership.id, :all))
  end

  defp with_location_scope(entry, _user_id), do: entry
end
