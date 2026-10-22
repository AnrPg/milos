defmodule Palee.Application.EventNotices do
  @moduledoc """
  What people hear about a club event (ADR-153): a place freed up for them,
  the event was cancelled or moved, it starts in two hours, a friend took
  their guest pass, the box's trial offer after the event, and staff's
  «Μήνυμα σε όλους». One notification per person; the copy lives in the
  notifications catalogs (12 locales).
  """

  alias Palee.{Community, Notifications, Organizations}
  alias Palee.TimeZones.ZonedTime

  def promoted(event, attendees),
    do:
      each(attendees, event, :community_event_waitlist_promoted, fn attendee ->
        %{dedupe: "#{attendee.user_id}:#{stamp(attendee.promoted_at)}"}
      end)

  def cancelled(event, attendees),
    do:
      each(attendees, event, :community_event_cancelled, fn _attendee ->
        %{reason: event.cancel_reason, dedupe: event.id}
      end)

  def changed(event, attendees, changes),
    do:
      each(attendees, event, :community_event_changed, fn _attendee ->
        %{
          changes: Enum.map_join(changes, ",", &Atom.to_string/1),
          dedupe: stamp(event.updated_at)
        }
      end)

  def reminder(event, attendees),
    do:
      each(attendees, event, :community_event_reminder, fn _attendee ->
        %{dedupe: stamp(event.starts_at)}
      end)

  def guest_joined(event, inviter_id, guest_id, guest_nickname),
    do:
      each([%{user_id: inviter_id}], event, :community_event_guest_joined, fn _attendee ->
        %{person_nickname: guest_nickname, dedupe: guest_id}
      end)

  def trial_offer(event, attendees, box),
    do:
      each(attendees, event, :community_event_trial_offer, fn _attendee ->
        %{
          box_name: box.name,
          url: "/b/#{box.slug}?trial=1&referral_event_id=#{event.id}",
          dedupe: event.id
        }
      end)

  def message(event, attendees, body, sent_at),
    do:
      each(attendees, event, :community_event_message, fn _attendee ->
        %{message: body, dedupe: stamp(sent_at)}
      end)

  defp each(recipients, event, type, extra) do
    zone = time_zone(event)
    event_when = ZonedTime.format(event.starts_at, zone)

    Enum.each(recipients, fn recipient ->
      Notifications.dispatch_event(
        type,
        Map.merge(
          %{
            user_id: recipient.user_id,
            organization_id: event.organization_id,
            club_id: event.club_id,
            event_id: event.id,
            event_title: event.title,
            event_starts_at: event.starts_at,
            event_when: event_when,
            time_zone: zone
          },
          extra.(recipient)
        )
      )
    end)
  end

  defp stamp(nil), do: "none"
  defp stamp(%DateTime{} = at), do: at |> DateTime.to_unix(:microsecond) |> Integer.to_string()

  @doc """
  When the event starts on the clock it is planned on («24/10 19:00»). Push
  texts add each reader's own time when theirs differs (ADR-179).
  """
  def event_when(%{starts_at: starts_at} = event),
    do: ZonedTime.format(starts_at, time_zone(event))

  @doc "ADR-179: the event's zone: its own when held away, else its gym's."
  def time_zone(%{organization_id: organization_id} = event),
    do: Community.event_time_zone(event, Organizations.organization_timezone(organization_id))
end
