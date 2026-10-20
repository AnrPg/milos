defmodule MilosTraining.Application.BodyReminders do
  @moduledoc """
  The opt-in measure reminder (ADR-158): a person who chose «remind me every
  N weeks» hears once, N weeks after their last snapshot (or the last
  reminder, or turning it on). A definer lookup names who is due; each
  person is then handled in their own session, marked before they are told,
  and the notification's dedupe key holds it to one a day even if the job
  retries.
  """

  require Logger

  alias MilosTraining.{Body, Notifications}

  @batch 200

  def call(now \\ DateTime.utc_now()), do: sweep(now, MapSet.new())

  defp sweep(now, seen) do
    due = now |> Body.reminders_due(@batch) |> Enum.reject(&MapSet.member?(seen, &1))

    case due do
      [] ->
        :ok

      user_ids ->
        Enum.each(user_ids, &remind(&1, now))
        sweep(now, MapSet.union(seen, MapSet.new(user_ids)))
    end
  end

  @doc "One person's reminder, when due (public for tests)."
  def remind(user_id, now) do
    context = %{user_id: user_id}
    settings = Body.settings(context, user_id)
    last_taken_at = Body.latest_taken_at(context, user_id)

    if Body.reminder_due?(settings, last_taken_at, now) do
      :ok = Body.mark_reminded(context, user_id, now)

      Notifications.dispatch_event(:body_measure_reminder, %{
        user_id: user_id,
        weeks: settings.measure_reminder_weeks,
        dedupe_key: Body.reminder_dedupe_key(user_id, DateTime.to_date(now))
      })
    else
      :ok
    end
  rescue
    error ->
      Logger.error("body reminder #{user_id} failed: #{Exception.message(error)}")
      :error
  end
end
