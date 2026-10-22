defmodule Palee.Application.ClassWorkoutAlerts do
  @moduledoc """
  Tells staff about classes still without their WOD on the day (ADR-176):
  at 07:00 that morning and one hour before the class, in the gym's time
  zone. A sweep every few minutes sends the latest alert each class owes;
  the notification's dedupe key (class, alert, start) makes overlapping
  sweeps and retries harmless, and a class moved to another time owes new
  alerts. Linking a WOD ends them.

  Who hears: the gym's staff who manage the schedule, and the class's coach.
  """

  alias Palee.{Notifications, Organizations, Scheduling}
  alias Palee.TimeZones.ZonedTime

  def call(now \\ DateTime.utc_now()) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      sweep(%{organization_id: organization.id}, now)
    end)
  end

  def sweep(%{organization_id: organization_id} = context, %DateTime{} = now) do
    to = DateTime.add(now, Scheduling.class_workout_alert_horizon_hours(), :hour)

    case Scheduling.list_slots_missing_workout(context, now, to) do
      [] ->
        :ok

      slots ->
        zone = Organizations.organization_timezone(organization_id)
        planners = Organizations.list_user_ids_with_capability(organization_id, :manage_schedule)

        Enum.each(slots, fn slot ->
          case Scheduling.class_workout_alert_due(slot, now, zone) do
            nil -> :ok
            {kind, _at} -> notify(slot, kind, zone, recipients(planners, slot))
          end
        end)
    end
  end

  defp recipients(planners, slot),
    do: Enum.uniq(planners ++ List.wrap(Map.get(slot, :coach_user_id)))

  defp notify(slot, kind, zone, recipients) do
    payload = %{
      organization_id: slot.organization_id,
      scheduled_class_id: slot.id,
      class_name: slot.name,
      class_starts_at: slot.scheduled_at,
      class_when: ZonedTime.format(slot.scheduled_at, zone),
      alert: Atom.to_string(kind),
      published: Scheduling.class_published?(slot),
      dedupe_key:
        "class_workout_missing:#{slot.id}:#{kind}:#{DateTime.to_unix(slot.scheduled_at)}"
    }

    Enum.each(recipients, fn user_id ->
      Notifications.dispatch_event(:class_workout_missing, Map.put(payload, :user_id, user_id))
    end)
  end
end
