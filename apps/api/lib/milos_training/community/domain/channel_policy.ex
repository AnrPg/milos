defmodule MilosTraining.Community.Domain.ChannelPolicy do
  @moduledoc """
  Who is in a club and its channels, and who may write where (ADR-138,
  vision §7.1 channel governance). Pure: callers pass the facts.

  A member's club role is `"staff"` when they hold a staff role in the gym
  that runs the club (owner, admin or coach), `"member"` otherwise.
  """

  @staff_roles ~w(owner admin coach)a

  # The channels every gym club starts with, in display order.
  @gym_channels [
    %{kind: "announcements", write_policy: "staff", membership: "everyone", position: 0},
    %{kind: "wod", write_policy: "system_and_members", membership: "everyone", position: 1},
    %{kind: "challenges", write_policy: "participants", membership: "opt_in", position: 2}
  ]

  def gym_channels, do: @gym_channels

  # D7: a member who booked the same class this often in the window is
  # offered its group.
  @suggest_bookings 3
  @suggest_window_days 28

  def class_group_suggestion,
    do: %{bookings: @suggest_bookings, window_days: @suggest_window_days}

  @doc "The channel a recurring class gets (D7): its regulars talk there."
  def class_slot_channel(%{id: series_id, name: name, local_start_time: start}) do
    time = if start, do: " " <> String.slice(Time.to_string(start), 0, 5), else: ""

    %{
      kind: "class_slot",
      name: String.slice(name || "", 0, 60 - String.length(time)) <> time,
      write_policy: "participants",
      membership: "opt_in",
      context_type: "class_series",
      context_id: series_id,
      position: 10
    }
  end

  @doc """
  The channel a season gets in the gym's club (ADR-167, vision §7.1
  «#hyrox-prep (season)»): invite-only, so only confirmed participants (and
  staff, who run it) see it; coach and participants write.
  """
  def season_channel(%{id: offering_id, title: title}) do
    %{
      kind: "season",
      name: String.slice(title || "", 0, 60),
      write_policy: "participants",
      membership: "invite",
      context_type: "season_offering",
      context_id: offering_id,
      position: 20
    }
  end

  @doc "Members to offer a class group: frequent bookers of that class."
  def class_group_candidates(counts) do
    for %{series_id: series_id, user_id: user_id, count: count} <- counts,
        count >= @suggest_bookings,
        do: {series_id, user_id}
  end

  @doc "The club role a gym membership's roles give."
  def club_role(%{roles: [_ | _] = roles}), do: club_role(roles)
  def club_role(%{role: role}) when not is_nil(role), do: club_role([role])
  def club_role(%{}), do: "member"

  def club_role(roles) when is_list(roles) do
    roles = Enum.map(roles, &to_role/1)
    if Enum.any?(roles, &(&1 in @staff_roles)), do: "staff", else: "member"
  end

  @doc "Whether the member reads this channel's posts in their feed."
  def in_feed?(%{membership: "everyone"}, _joined?), do: true
  def in_feed?(_channel, joined?), do: joined? == true

  @doc "Whether a member may join or leave the channel on their own."
  def self_service?(%{membership: "opt_in", archived_at: nil}), do: true
  def self_service?(_channel), do: false

  @doc "Whether someone with `role` (and channel participation) may post."
  def can_post?(%{archived_at: archived_at}, _role, _joined?) when not is_nil(archived_at),
    do: false

  # A proposed or declined group is read-only (ADR-143).
  def can_post?(%{status: status}, _role, _joined?) when status in ["pending", "declined"],
    do: false

  # In a member group only its members write, staff included (ADR-143).
  def can_post?(%{kind: "member_group"}, _role, joined?), do: joined? == true

  def can_post?(%{write_policy: "staff"}, role, _joined?), do: role == "staff"
  def can_post?(%{write_policy: "members"}, _role, _joined?), do: true
  def can_post?(%{write_policy: "system_and_members"}, _role, _joined?), do: true

  def can_post?(%{write_policy: "participants"}, role, joined?),
    do: role == "staff" or joined? == true

  def can_post?(_channel, _role, _joined?), do: false

  @doc "Staff moderate every post in their club; authors remove their own (D8)."
  def can_delete_post?(post, user_id, role),
    do: post.author_id == user_id or role == "staff"

  def can_moderate?(role), do: role == "staff"

  @doc """
  The role someone acts with inside one channel: a member group's admins
  moderate their group the way staff moderate the club (ADR-143).
  """
  def channel_role("staff", _channel), do: "staff"
  def channel_role(_role, %{kind: "member_group", admin: true}), do: "staff"
  def channel_role(role, _channel), do: role

  @doc "Staff pin in channels staff write to; group admins pin in their group."
  def can_pin?(%{write_policy: "staff"}, "staff"), do: true
  def can_pin?(%{kind: "member_group"}, "staff"), do: true
  def can_pin?(%{kind: "season"}, "staff"), do: true
  def can_pin?(_channel, _role), do: false

  defp to_role(role) when is_atom(role), do: role

  defp to_role(role) when is_binary(role) do
    Enum.find(@staff_roles, :member, &(Atom.to_string(&1) == role))
  end
end
