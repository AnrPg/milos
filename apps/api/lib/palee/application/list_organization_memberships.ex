defmodule Palee.Application.ListOrganizationMemberships do
  @moduledoc """
  The account's memberships for the session payload, each with the branches
  the person works at as staff (ADR-186), so the capabilities it carries are
  the narrowed ones the API enforces.

  ADR-272: a membership that only makes the person a guest of a box is not
  one of their gyms either (the member app and the console stay closed to
  it); `guest_boxes/1` lists those boxes for the box page's banner.
  """

  alias Palee.Organizations

  def call(%{id: user_id}) do
    {:ok,
     user_id
     |> Organizations.list_memberships()
     # ADR-185 / ADR-272: no organiser organisation, no box one is only a guest of.
     |> Organizations.provider_memberships()
     |> Enum.map(&with_location_scope(&1, user_id))}
  end

  @doc "ADR-272: the boxes the person is only a guest of (`id`, `name`, `slug`)."
  def guest_boxes(%{id: user_id}) do
    {:ok,
     user_id
     |> Organizations.list_memberships()
     |> Enum.reject(&Organizations.hosting_only?/1)
     |> Enum.filter(&(Organizations.guest_only?(&1) and &1.membership.status == :active))
     |> Enum.map(fn %{organization: organization} ->
       %{id: organization.id, name: organization.name, slug: organization.slug}
     end)}
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
