defmodule Palee.Application.ListAthletes do
  @moduledoc """
  Lists the users an assignment may target in the acting organization.

  By default only active athletes. With `include_members: true` (ADR-125) active
  members are listed too; whether a member may actually receive personal
  programming is decided by their package when the assignment is created.
  """

  alias Palee.Application.BranchReport
  alias Palee.{Identity, Organizations}

  def call(context, query, opts \\ [])

  def call(%{organization_id: organization_id} = context, query, opts)
      when is_binary(organization_id) do
    roles =
      if Keyword.get(opts, :include_members, false), do: [:athlete, :member], else: [:athlete]

    roles_by_user = active_roles(organization_id, roles)

    roles_by_user
    |> Map.keys()
    |> at_branches(context, Keyword.get(opts, :location_ids, []))
    |> Identity.list_by_ids()
    |> filter_query(query)
    |> Enum.map(&%{id: &1.id, nickname: &1.nickname, role: to_string(roles_by_user[&1.id])})
    |> Enum.sort_by(&String.downcase(&1.nickname || ""))
  end

  def call(_context, _query, _opts), do: {:error, :organization_context_required}

  def call(_query), do: {:error, :organization_context_required}

  # user id => tenant membership role, for active memberships with one of
  # `roles`. The role shown to staff is the membership role (F-29).
  defp active_roles(organization_id, roles) do
    organization_id
    |> Organizations.list_active_membership_user_ids()
    |> Enum.flat_map(fn user_id ->
      user_id
      |> Organizations.list_memberships()
      |> Enum.find_value([], fn %{membership: membership, organization: organization} ->
        if organization.id == organization_id and membership.status == :active and
             membership.role in roles,
           do: [{user_id, membership.role}]
      end)
    end)
    |> Map.new()
  end

  # ADR-186 §7: the coaching page's branch filter keeps the people whose home
  # branch is one of the requested ones (inside the person's scope). Pickers
  # name no branches and keep everyone.
  defp at_branches(user_ids, _context, []), do: user_ids

  defp at_branches(user_ids, context, location_ids) do
    case BranchReport.resolve(context, %{"location_ids" => location_ids}) do
      %{user_ids: nil} -> user_ids
      %{user_ids: users} -> Enum.filter(user_ids, &(&1 in users))
    end
  end

  defp filter_query(users, query) when is_binary(query) and query != "" do
    normalized_query = String.downcase(query)

    Enum.filter(users, fn user ->
      String.contains?(String.downcase(user.nickname || ""), normalized_query)
    end)
  end

  defp filter_query(users, _query), do: users
end
