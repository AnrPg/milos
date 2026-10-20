defmodule MilosTraining.Community.Domain.GroupPolicy do
  @moduledoc """
  Member groups in a gym's club (ADR-143, board 7 Q2, Q3, Q8). Pure: callers
  pass the facts.

  - The owner chooses whether members may start groups (`none`), whether
    staff approve each one first (`approval`, the default) or not (`free`).
    Staff can always start one, and theirs need no approval.
  - Whoever starts a group is its first admin. Admins let people in when the
    group asks for that, pin and hide posts in it, and edit it. The last
    admin hands over before leaving while others remain; the last member
    leaving archives it.
  - A group nobody posts in for 50 days is warned; at 60 it is
    archived. Its creator or staff can reopen it.
  """

  @warn_after_days 50
  @archive_after_days 60

  def lifecycle, do: %{warn_after_days: @warn_after_days, archive_after_days: @archive_after_days}

  @doc "Whether someone with this club role may start a group under `setting`."
  def can_propose?("staff", _setting), do: true
  def can_propose?(_role, setting), do: setting in ["approval", "free"]

  @doc "The status a new group starts in."
  def initial_status("staff", _setting), do: "active"
  def initial_status(_role, "free"), do: "active"
  def initial_status(_role, _setting), do: "pending"

  @doc "The channel a group is: everyone in it writes, nobody outside reads."
  def channel_spec(attrs) do
    %{
      kind: "member_group",
      name: Map.get(attrs, :name),
      description: Map.get(attrs, :description),
      join_policy: Map.get(attrs, :join_policy) || "open",
      write_policy: "participants",
      membership: "invite",
      position: 20
    }
  end

  @doc "What joining does: an open group lets you in, the other kind asks its admins."
  def join_source(%{join_policy: "open"}), do: "opt_in"
  def join_source(%{join_policy: "request"}), do: "requested"

  @doc "Whether people can join or post: only a live group staff let through."
  def live?(%{kind: "member_group", status: "active", archived_at: nil}), do: true
  def live?(_channel), do: false

  @doc "Admins of the group and the gym's staff run it."
  def can_manage?(_membership_role, "staff"), do: true
  def can_manage?("admin", _club_role), do: true
  def can_manage?(_membership_role, _club_role), do: false

  @doc "Whoever started a group, or staff, bring it back after it was archived."
  def can_reopen?(_group, "staff", _user_id), do: true
  def can_reopen?(%{created_by_id: creator}, _role, user_id), do: creator == user_id

  @doc "Only staff decide on a proposed group."
  def can_decide?(%{status: "pending"}, "staff"), do: true
  def can_decide?(_group, _club_role), do: false

  @doc """
  What leaving does for this member: `:leave`; `:archive` when they are the
  last one; `{:error, :hand_over_first}` when they are its only admin and
  others remain.
  """
  def on_leave(%{role: "admin"}, admins, members) when admins <= 1 and members > 1,
    do: {:error, :hand_over_first}

  def on_leave(_membership, _admins, members) when members <= 1, do: :archive
  def on_leave(_membership, _admins, _members), do: :leave

  @doc """
  What the daily sweep does to a live group, given when it was last active
  (its last post, or when it went live) and whether it was warned since.
  """
  def quiet_step(%{archive_warned_at: warned_at} = group, now) do
    quiet_days = DateTime.diff(now, last_active_at(group), :day)

    cond do
      quiet_days >= @archive_after_days and not is_nil(warned_at) -> :archive
      quiet_days >= @warn_after_days and is_nil(warned_at) -> :warn
      true -> :none
    end
  end

  @doc "The latest moment a group counts as active before it is swept at `now`."
  def warn_cutoff(now), do: DateTime.add(now, -@warn_after_days, :day)

  def last_active_at(group),
    do: group.last_post_at || group.decided_at || group.inserted_at
end
