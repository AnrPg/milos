defmodule MilosTraining.Application.EventNotices do
  @moduledoc """
  What people hear about a club event (ADR-153): a place freed up for them,
  the event was cancelled or moved, it starts in two hours, a friend took
  their guest pass, the box's trial offer after the event, and staff's
  «Μήνυμα σε όλους». One notification per person; the copy lives in the
  notifications catalogs (12 locales).
  """

  alias MilosTraining.{Notifications, Organizations}

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
    event_when = event_when(event)

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
            event_when: event_when
          },
          extra.(recipient)
        )
      )
    end)
  end

  defp stamp(nil), do: "none"
  defp stamp(%DateTime{} = at), do: at |> DateTime.to_unix(:microsecond) |> Integer.to_string()

  @doc "When the event starts, in the box's time zone («24/10 19:00»)."
  def event_when(%{starts_at: starts_at, organization_id: organization_id}) do
    zone = Organizations.organization_timezone(organization_id)

    case DateTime.shift_zone(starts_at, zone) do
      {:ok, local} -> Calendar.strftime(local, "%d/%m %H:%M")
      {:error, _reason} -> Calendar.strftime(starts_at, "%d/%m %H:%M UTC")
    end
  end
end
