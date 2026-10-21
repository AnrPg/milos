defmodule Palee.Community.Domain.SquadPolicy do
  @moduledoc """
  PT squads (ADR-168, vision §7.1 «PT squad · A coach · Coach + their
  clients · Invite-only»). Pure: callers pass the facts.

  - A coach of the gym starts a squad in the gym's club and is its only
    admin. Squads are small: at most 30 people besides the coach, and a
    coach runs at most 20 live squads.
  - Only the coach's own active clients can be invited. An invitation waits
    for the client (`pending_invite`); accepting makes them a member
    (`invited`), declining or leaving dismisses it. The coach may invite a
    dismissed client again: a new invitation asks again.
  - Membership follows coaching: when the coaching ends the client leaves
    every squad of that coach, and a squad never shows to a client whose
    coaching with its coach is no longer active.
  - Squads never auto-archive (the coach runs them); the coach or the gym's
    managers archive one, and only the coach brings it back.
  - Only the coach and members see a squad, its posts and its people. Other
    staff don't: it is the coach's space with their clients, and reports
    still reach staff through the report queue.
  """

  @max_members 30
  @max_live_squads 20

  @member_sources ~w(invited auto)

  def limits, do: %{max_members: @max_members, max_live_squads: @max_live_squads}

  @doc "Whether someone holding these gym roles may start and run squads."
  def can_coach?(roles), do: Enum.any?(roles, &(&1 in [:coach, "coach"]))

  def can_create?(roles, live_squads) do
    cond do
      not can_coach?(roles) -> {:error, :not_a_coach}
      live_squads >= @max_live_squads -> {:error, :too_many_squads}
      true -> :ok
    end
  end

  @doc "The channel a squad is: everyone in it writes, nobody outside reads."
  def channel_spec(attrs) do
    %{
      kind: "pt_squad",
      name: Map.get(attrs, :name),
      description: Map.get(attrs, :description),
      write_policy: "participants",
      membership: "invite",
      position: 30
    }
  end

  @doc "The squad's coach runs it; the gym's managers may also archive it."
  def coach?(%{created_by_id: coach_id}, user_id), do: coach_id == user_id

  def can_archive?(squad, user_id, manager?), do: coach?(squad, user_id) or manager? == true

  def live?(%{kind: "pt_squad", archived_at: nil}), do: true
  def live?(_channel), do: false

  def member?(%{source: source}), do: source in @member_sources
  def member?(_membership), do: false

  def invited?(%{source: "pending_invite"}), do: true
  def invited?(_membership), do: false

  @doc """
  Whom of `user_ids` the coach can invite now, given their active clients and
  the squad's current memberships; `{:error, :squad_full}` when the
  invitations would take the squad over its size.
  """
  def invitees(user_ids, client_ids, memberships, coach_id) do
    clients = MapSet.new(client_ids)
    current = Map.new(memberships, &{&1.user_id, &1})

    wanted =
      user_ids
      |> Enum.uniq()
      |> Enum.reject(&(&1 == coach_id))

    case Enum.reject(wanted, &MapSet.member?(clients, &1)) do
      [] ->
        fresh =
          Enum.reject(wanted, fn user_id ->
            membership = Map.get(current, user_id)
            member?(membership) or invited?(membership)
          end)

        taken =
          Enum.count(memberships, &((member?(&1) or invited?(&1)) and &1.user_id != coach_id))

        if taken + length(fresh) > @max_members,
          do: {:error, :squad_full},
          else: {:ok, fresh}

      _not_clients ->
        {:error, :not_your_client}
    end
  end

  @doc "What answering an invitation sets."
  def answer_source(true), do: "invited"
  def answer_source(false), do: "dismissed"

  @doc """
  Whether a squad shows to this person: its coach always; a member while
  their coaching with the coach is active (`coach_ids` are their active
  coaches in that gym).
  """
  def visible?(squad, user_id, membership, coach_ids) do
    coach?(squad, user_id) or
      (member?(membership) and squad.created_by_id in coach_ids)
  end
end
