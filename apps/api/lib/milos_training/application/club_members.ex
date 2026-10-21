defmodule MilosTraining.Application.ClubMembers do
  @moduledoc """
  A club's «Μέλη» tab (ADR-143, board 7 Q1): everyone in the club except the
  viewer and those who chose to keep out of it, coaches first, then by name. A gym club's members are the gym's
  active members; an open club's are its active memberships. Each row says
  whether the viewer follows that person.
  """

  alias MilosTraining.Application.{ClubScope, CommunityPeople}
  alias MilosTraining.{Community, Organizations}

  @limit 500

  def list(%{user_id: user_id} = context, club_id, params \\ %{}) do
    with {:ok, club} <- ClubScope.club(context, club_id) do
      ids = member_ids(context, club) -- [user_id]
      ids = ids -- Community.hidden_member_ids(ids)
      coaches = MapSet.new(Organizations.list_staff(club.organization_id), & &1.user_id)
      followed = MapSet.new(Community.followed_ids(context, user_id, "user"))
      people = CommunityPeople.by_ids(ids)

      rows =
        ids
        |> Enum.map(&CommunityPeople.person(people, &1))
        |> Enum.filter(&matches?(&1.nickname, params[:q]))
        |> Enum.map(fn person ->
          Map.merge(person, %{
            coach: MapSet.member?(coaches, person.id),
            following: MapSet.member?(followed, person.id)
          })
        end)
        |> Enum.sort_by(&{not &1.coach, String.downcase(&1.nickname || "~")})

      {:ok, %{club_id: club.id, count: length(rows), members: Enum.take(rows, @limit)}}
    end
  end

  @doc """
  Everyone in the club, as the gym says right now: a gym club's members are
  the gym's active members; any other club's are its active memberships.
  Partners (ADR-169) re-checks eligibility with this on every read.
  """
  def member_ids(_context, %{kind: "gym", organization_id: organization_id}),
    do: Organizations.list_active_membership_user_ids(organization_id)

  def member_ids(context, club) do
    context
    |> then(&ClubScope.write_context(club, &1))
    |> Community.club_memberships(club.id, "active")
    |> Enum.map(& &1.user_id)
  end

  defp matches?(_nickname, query) when query in [nil, ""], do: true

  defp matches?(nickname, query),
    do: String.contains?(String.downcase(nickname || ""), String.downcase(String.trim(query)))
end
