defmodule Palee.Community.Commands.OpenClubs do
  @moduledoc """
  Open clubs (ADR-143): staff of a gym create and run them; anyone signed in
  can join one, straight away or after staff approve. Runs in the scope of
  the gym that runs the club.
  """

  alias Palee.Community.CommunityStore
  alias Palee.Community.Domain.ClubPolicy

  @editable [:name, :description, :cover_media_id, :join_policy]

  def create(%{user_id: user_id} = context, role, attrs) do
    with :ok <- staff(role),
         :ok <- join_policy(Map.get(attrs, :join_policy, "open")) do
      attrs =
        attrs
        |> Map.take(@editable)
        |> Map.put_new(:join_policy, "open")
        |> Map.put(:created_by_id, user_id)

      CommunityStore.create_club(context, attrs, ClubPolicy.channels())
    end
  end

  def update(context, club, role, attrs) do
    with :ok <- staff(role),
         :ok <- join_policy(Map.get(attrs, :join_policy, club.join_policy)),
         do: CommunityStore.update_club(context, club.id, Map.take(attrs, @editable))
  end

  def archive(context, club, role, now) do
    with :ok <- staff(role), do: CommunityStore.update_club(context, club.id, %{archived_at: now})
  end

  @doc "Joining: an open club lets you in, an approval club waits for staff."
  def join(%{user_id: user_id} = context, %{kind: "open"} = club) do
    case CommunityStore.get_club_membership(context, club.id, user_id) do
      %{status: status} ->
        {:ok, status}

      nil ->
        status = ClubPolicy.join_status(club)

        with {:ok, _membership} <-
               CommunityStore.put_club_membership(context, club, user_id, %{status: status}),
             do: {:ok, status}
    end
  end

  def join(_context, _club), do: {:error, :not_found}

  def leave(%{user_id: user_id} = context, %{kind: "open"} = club),
    do: CommunityStore.delete_club_membership(context, club.id, user_id)

  def leave(_context, _club), do: {:error, :not_found}

  def answer_request(context, club, role, user_id, approve?) do
    with :ok <- staff(role),
         %{status: "pending"} <-
           CommunityStore.get_club_membership(context, club.id, user_id) || {:error, :not_found} do
      if approve?,
        do: CommunityStore.put_club_membership(context, club, user_id, %{status: "active"}),
        else: CommunityStore.delete_club_membership(context, club.id, user_id)
    end
  end

  def set_notify_level(%{user_id: user_id} = context, club, level),
    do:
      with(
        {:ok, _membership} <-
          CommunityStore.put_club_membership(context, club, user_id, %{notify_level: level}),
        do: :ok
      )

  def remove_member(context, club, role, user_id) do
    with :ok <- staff(role), do: CommunityStore.delete_club_membership(context, club.id, user_id)
  end

  def memberships(context, club_id, status \\ nil),
    do: CommunityStore.list_club_memberships(context, club_id, status)

  def memberships_of(context, user_id), do: CommunityStore.club_memberships_of(context, user_id)
  def list(context, filter), do: CommunityStore.list_open_clubs(context, filter)
  def member_counts(context, ids), do: CommunityStore.open_club_member_counts(context, ids)
  def by_ids(context, ids), do: CommunityStore.list_clubs_by_ids(context, ids)

  defp staff(role), do: if(ClubPolicy.can_manage?(role), do: :ok, else: {:error, :forbidden})

  defp join_policy(policy),
    do: if(policy in ClubPolicy.join_policies(), do: :ok, else: {:error, :invalid_join_policy})
end
