defmodule MilosTraining.Community.Commands.Squads do
  @moduledoc """
  PT squads in a gym's club (ADR-168): a coach starts one, invites their own
  clients, renames and archives it; a client answers an invitation and may
  leave. Governance comes from `SquadPolicy`; the caller passes the facts it
  needs from other contexts (the coach's roles, their active clients).
  """

  alias MilosTraining.Community.CommunityStore
  alias MilosTraining.Community.Domain.SquadPolicy

  def create(%{user_id: user_id} = context, club, coach_roles, attrs) do
    live = context |> CommunityStore.list_squads(club.id, %{coach_id: user_id}) |> length()

    with :ok <- SquadPolicy.can_create?(coach_roles, live),
         do:
           CommunityStore.create_group(
             context,
             club,
             SquadPolicy.channel_spec(attrs),
             user_id,
             "active"
           )
  end

  def list(context, club_id, filter \\ %{}),
    do: CommunityStore.list_squads(context, club_id, filter)

  def members(context, squad_id), do: CommunityStore.list_channel_memberships(context, squad_id)

  def memberships_of(context, user_id), do: CommunityStore.squad_memberships_of(context, user_id)

  @doc "The coach invites some of their active clients (`client_ids`); returns who was invited."
  def invite(%{user_id: user_id} = context, squad, user_ids, client_ids) do
    with :ok <- coach(squad, user_id),
         :ok <- live(squad),
         {:ok, fresh} <-
           SquadPolicy.invitees(user_ids, client_ids, members(context, squad.id), user_id) do
      Enum.reduce_while(fresh, {:ok, fresh}, fn invitee, acc ->
        case CommunityStore.put_channel_membership(context, squad, invitee, %{
               source: "pending_invite"
             }) do
          :ok -> {:cont, acc}
          error -> {:halt, error}
        end
      end)
    end
  end

  @doc "The invited client accepts or declines."
  def answer(%{user_id: user_id} = context, squad, membership, accept?) do
    with :ok <- live(squad),
         true <- SquadPolicy.invited?(membership) || {:error, :not_found} do
      CommunityStore.put_channel_membership(context, squad, user_id, %{
        source: SquadPolicy.answer_source(accept?)
      })
    end
  end

  @doc "A member leaves; the coach can't leave their own squad (they archive it)."
  def leave(%{user_id: user_id} = context, squad, membership) do
    cond do
      SquadPolicy.coach?(squad, user_id) -> {:error, :coach_archives_instead}
      SquadPolicy.member?(membership) -> dismiss(context, squad, user_id)
      true -> {:error, :not_found}
    end
  end

  @doc "The coach removes a member or withdraws an invitation."
  def remove(%{user_id: user_id} = context, squad, target_id) do
    with :ok <- coach(squad, user_id),
         true <- target_id != user_id || {:error, :coach_archives_instead},
         %{} = membership <-
           Enum.find(members(context, squad.id), &(&1.user_id == target_id)) ||
             {:error, :not_found},
         true <-
           (SquadPolicy.member?(membership) or SquadPolicy.invited?(membership)) ||
             {:error, :not_found},
         do: dismiss(context, squad, target_id)
  end

  def update(%{user_id: user_id} = context, squad, attrs) do
    with :ok <- coach(squad, user_id),
         :ok <- live(squad),
         do:
           CommunityStore.update_squad(
             context,
             squad.id,
             Map.take(attrs, [:name, :description])
           )
  end

  def archive(%{user_id: user_id} = context, squad, manager?, now) do
    if SquadPolicy.can_archive?(squad, user_id, manager?),
      do: CommunityStore.set_squad_archived(context, squad.id, now),
      else: {:error, :forbidden}
  end

  def reopen(%{user_id: user_id} = context, squad) do
    with :ok <- coach(squad, user_id),
         live = context |> CommunityStore.list_squads(squad.club_id, %{coach_id: user_id}),
         :ok <- under_limit(live),
         do: CommunityStore.set_squad_archived(context, squad.id, nil)
  end

  @doc "Coaching between them ended: the client leaves every squad of that coach."
  def coaching_ended(context, coach_id, client_id),
    do: CommunityStore.dismiss_from_coach_squads(context, coach_id, client_id)

  defp under_limit(live) do
    if length(live) >= SquadPolicy.limits().max_live_squads,
      do: {:error, :too_many_squads},
      else: :ok
  end

  defp coach(squad, user_id),
    do: if(SquadPolicy.coach?(squad, user_id), do: :ok, else: {:error, :forbidden})

  defp live(squad), do: if(SquadPolicy.live?(squad), do: :ok, else: {:error, :squad_archived})

  defp dismiss(context, squad, user_id),
    do: CommunityStore.put_channel_membership(context, squad, user_id, %{source: "dismissed"})
end
