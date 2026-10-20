defmodule MilosTraining.Application.EventReminders do
  @moduledoc """
  The reminder two hours before a club event (ADR-153), sent by a sweep
  every few minutes. Each event is claimed (`reminder_sent_at`) before
  anyone is told, so overlapping sweeps or retries never remind twice; an
  event moved to a later start owes a new reminder.
  """

  alias MilosTraining.Application.EventNotices
  alias MilosTraining.{Community, Organizations}

  def call(now \\ DateTime.utc_now()) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      sweep(%{organization_id: organization.id}, now)
    end)
  end

  def sweep(context, now) do
    window = %{from: now, to: DateTime.add(now, Community.event_reminder_minutes(), :minute)}

    context
    |> Community.events_reminder_due(window)
    |> Enum.filter(&Community.event_reminder_due?(&1, now))
    |> Enum.each(fn event ->
      with {:ok, claimed} <- Community.claim_event_step(context, event.id, :reminder_sent_at, now) do
        EventNotices.reminder(claimed, Community.list_attendees(context, [event.id], ["going"]))
      end
    end)
  end
end
