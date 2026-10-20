defmodule MilosTraining.Community.Domain.EventPolicy do
  @moduledoc """
  The rules of an event (ADR-153, board 8). Pure: callers pass the facts.

  * **Who comes.** People who can see the club come as `member`s; anyone
    signed in comes to an event `open_to_non_members` as `open`; a friend a
    going member invited comes as that member's `guest`, up to
    `guests_per_member` per member, while guest passes are allowed.
  * **Places.** «Θα έρθω» takes a place while there is one and otherwise
    joins the waitlist; a freed place goes to whoever has waited longest.
    Lowering the capacity never removes anyone already going.
  * **Late cancels.** Giving up a place less than #{120} minutes before the
    start is a late cancel.
  * **Member groups.** An admin of an active member group runs events for
    the group: always free, never open to non-members, no guest passes. Only
    the group's members see them and come; staff who run events manage
    them like any other.
  * **After.** One trial offer, once the event ended, to the people who came
    and are not members of the box. Coming and then joining the box within
    #{30} days counts as a conversion.
  """

  @late_cancel_minutes 120
  @reminder_minutes 120
  @conversion_days 30
  @scopes ~w(this following)
  @late_cancel_window_days 90
  @group_terms %{price_cents: 0, open_to_non_members: false, guest_pass_allowed: false}

  def late_cancel_minutes, do: @late_cancel_minutes
  def reminder_minutes, do: @reminder_minutes
  def conversion_days, do: @conversion_days
  def scopes, do: @scopes
  def late_cancel_window_days, do: @late_cancel_window_days

  @doc "The capability that creates and runs events (owner, admin, coach)."
  def capability, do: :manage_events

  # Member groups ---------------------------------------------------------------

  @doc "A group event's terms win over whatever was asked: free, the group only."
  def group_terms(attrs), do: Map.merge(attrs, @group_terms)

  @doc "An event can go in an active, live member group of the same club."
  def group_channel_check(
        %{kind: "member_group", status: "active", archived_at: nil} = channel,
        club_id
      ) do
    if channel.club_id == club_id, do: :ok, else: {:error, :not_found}
  end

  def group_channel_check(_channel, _club_id), do: {:error, :not_found}

  @doc """
  An admin of the group (`membership` is `%{member?: boolean, role: role}`
  or nil) while the group is active and live.
  """
  def group_admin?(channel, %{member?: true, role: "admin"}),
    do: group_channel_check(channel, Map.get(channel, :club_id)) == :ok

  def group_admin?(_channel, _membership), do: false

  @doc """
  Who may create, edit and cancel: holders of `manage_events` any event at
  their box; a group's admin the events of their group (`channel_id`).
  """
  def manage_check(%{manage_events?: true}, _channel_id), do: :ok

  def manage_check(%{group_admin?: true}, channel_id) when is_binary(channel_id), do: :ok
  def manage_check(_actor, _channel_id), do: {:error, :forbidden}

  @doc """
  Whether the person belongs to the event's audience: the club's members
  for a club event, the group's members for a group event.
  """
  def belongs?(%{channel_id: nil}, %{club_member?: club_member?}), do: club_member? == true
  def belongs?(_group_event, facts), do: Map.get(facts, :group_member?) == true

  @doc """
  Whether the person may see the event: they belong, it is open (or they
  were invited) when it isn't a group's, they run it, or they are on it.
  """
  def visible?(event, %{belongs?: belongs?} = facts) do
    belongs? or Map.get(facts, :manager?) == true or Map.get(facts, :attendee?) == true or
      (is_nil(event.channel_id) and
         (event.open_to_non_members or Map.get(facts, :invited?) == true))
  end

  @doc """
  Whether «Θα έρθω» / «Δεν θα έρθω» shows: still open, and the person
  belongs, it is open to everyone (not a group's), or they hold a row.
  """
  def can_rsvp?(event, belongs?, my_status, now) do
    open_for_rsvp(event, now) == :ok and
      (belongs? or (is_nil(event.channel_id) and event.open_to_non_members) or
         my_status in ~w(going waitlisted))
  end

  @doc """
  How the person may come: `{:ok, "member"}` when they can see the club,
  `{:ok, "open"}` on an open event, `{:ok, {"guest", inviter_id}}` with a
  valid invitation, else `{:error, :not_invited}`.
  """
  def source(%{club_member?: true}), do: {:ok, "member"}
  def source(%{open?: true}), do: {:ok, "open"}

  def source(%{invited_by: inviter_id}) when is_binary(inviter_id),
    do: {:ok, {"guest", inviter_id}}

  def source(_facts), do: {:error, :not_invited}

  @doc "Whether people can still say they come (or don't): not cancelled, not started."
  def open_for_rsvp(%{cancelled_at: cancelled_at}, _now) when not is_nil(cancelled_at),
    do: {:error, :event_cancelled}

  def open_for_rsvp(%{starts_at: starts_at}, now) do
    if DateTime.compare(starts_at, now) == :gt, do: :ok, else: {:error, :event_started}
  end

  @doc "Where «Θα έρθω» puts someone, given how many are going."
  def join_status(%{capacity: nil}, _going), do: "going"
  def join_status(%{capacity: capacity}, going) when going < capacity, do: "going"
  def join_status(_event, _going), do: "waitlisted"

  @doc "Places left (nil: no limit)."
  def spots_left(%{capacity: nil}, _going), do: nil
  def spots_left(%{capacity: capacity}, going), do: max(capacity - going, 0)

  @doc """
  Whether a going member may bring one more guest: guest passes on, the
  member going, fewer guests than `guests_per_member`.
  """
  def guest_check(%{guest_pass_allowed: false}, _inviter_status, _guests),
    do: {:error, :guests_not_allowed}

  def guest_check(_event, inviter_status, _guests) when inviter_status != "going",
    do: {:error, :inviter_not_going}

  def guest_check(%{guests_per_member: limit}, _inviter_status, guests) when guests >= limit,
    do: {:error, :guest_limit_reached}

  def guest_check(_event, _inviter_status, _guests), do: :ok

  @doc "Giving up a held place close to the start is a late cancel."
  def late_cancel?("going", %{starts_at: starts_at}, now),
    do: DateTime.diff(starts_at, now, :second) < @late_cancel_minutes * 60

  def late_cancel?(_status, _event, _now), do: false

  @doc """
  Who moves up from the waitlist: the longest-waiting first, as many as
  there are free places. `waitlisted` must be in queue order.
  """
  def promotions(%{capacity: nil}, _going, waitlisted), do: waitlisted

  def promotions(%{capacity: capacity}, going, waitlisted),
    do: Enum.take(waitlisted, max(capacity - going, 0))

  @doc "Names of who's going show to people who can see the club; others see a count."
  def show_names?(club_member?), do: club_member? == true

  @doc "What changed that people going should hear about: `:time`, `:place`, or both."
  def notable_changes(earlier, later) do
    time? =
      DateTime.compare(earlier.starts_at, later.starts_at) != :eq or
        DateTime.compare(earlier.ends_at, later.ends_at) != :eq

    place? =
      Enum.any?(
        [:location_id, :place_name, :address, :latitude, :longitude],
        &(Map.get(earlier, &1) != Map.get(later, &1))
      )

    Enum.filter([time: time?, place: place?], &elem(&1, 1)) |> Enum.map(&elem(&1, 0))
  end

  @doc "Whether the reminder is due now: within #{@reminder_minutes} minutes of the start."
  def reminder_due?(%{cancelled_at: nil, reminder_sent_at: nil, starts_at: starts_at}, now) do
    seconds = DateTime.diff(starts_at, now, :second)
    seconds > 0 and seconds <= @reminder_minutes * 60
  end

  def reminder_due?(_event, _now), do: false

  @doc "A changed start owes a new reminder when it is still ahead."
  def reset_reminder?(%{starts_at: earlier}, %{starts_at: later}, now),
    do: DateTime.compare(earlier, later) != :eq and DateTime.compare(later, now) == :gt

  @doc "The trial offer goes once, after the event ended."
  def trial_offer_check(%{cancelled_at: cancelled_at}, _now) when not is_nil(cancelled_at),
    do: {:error, :event_cancelled}

  def trial_offer_check(%{trial_offer_sent_at: sent}, _now) when not is_nil(sent),
    do: {:error, :trial_offer_already_sent}

  def trial_offer_check(%{ends_at: ends_at}, now) do
    if DateTime.compare(ends_at, now) == :gt, do: {:error, :event_not_over}, else: :ok
  end

  @doc "Who gets the trial offer: people who came and are not members of the box."
  def trial_offer_recipients(attendees, member_ids) do
    members = MapSet.new(member_ids)

    Enum.filter(attendees, fn attendee ->
      attendee.status == "going" and not is_nil(attendee.checked_in_at) and
        is_nil(attendee.trial_offered_at) and not MapSet.member?(members, attendee.user_id)
    end)
  end

  @doc "Staff record a payment once, for a place someone holds on a paid event."
  def payment_check(%{price_cents: 0}, _attendee), do: {:error, :event_is_free}

  def payment_check(_event, %{paid_at: paid_at}) when not is_nil(paid_at),
    do: {:error, :already_paid}

  def payment_check(_event, %{status: "going"}), do: :ok
  def payment_check(_event, _attendee), do: {:error, :not_going}

  @doc "Ήρθε is for people holding a place."
  def check_in_check(%{cancelled_at: cancelled_at}, _attendee) when not is_nil(cancelled_at),
    do: {:error, :event_cancelled}

  def check_in_check(_event, %{status: "going"}), do: :ok
  def check_in_check(_event, _attendee), do: {:error, :not_going}

  @doc """
  An event's numbers for staff: going, came, no-shows (going but not
  checked in once it ended), late cancels, trial requests that came from
  its offer and people who joined the box within #{@conversion_days} days.
  """
  def stats(event, attendees, trial_requests, now) do
    going = Enum.filter(attendees, &(&1.status == "going"))
    came = Enum.count(going, &(not is_nil(&1.checked_in_at)))
    over? = DateTime.compare(event.ends_at, now) != :gt

    %{
      going: length(going),
      waitlisted: Enum.count(attendees, &(&1.status == "waitlisted")),
      guests: Enum.count(going, &(&1.source == "guest")),
      paid: Enum.count(going, &(not is_nil(&1.paid_at))),
      came: came,
      no_shows: if(over?, do: length(going) - came, else: 0),
      late_cancels: Enum.count(attendees, & &1.late_cancel),
      trial_requests: trial_requests,
      converted: Enum.count(attendees, &(not is_nil(&1.converted_at)))
    }
  end
end
