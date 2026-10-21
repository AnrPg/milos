defmodule MilosTraining.Application.WellnessNudges do
  @moduledoc """
  Sends the craving follow-up and the opt-in water reminder (ADR-159). A
  definer lookup names who is due; each person is then handled in their own
  session, marked before they are told, and the notification's dedupe key
  holds each nudge to one even if the job retries. A journal section the
  member switched off stays silent (ADR-158 settings).
  """

  require Logger

  alias MilosTraining.Application.WellnessInput
  alias MilosTraining.{Body, Notifications, Wellness}
  alias MilosTraining.Wellness.Domain.NudgePolicy

  @batch 200

  def call(now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)
    sweep(&Wellness.craving_follow_ups_due/2, &follow_up/3, now, MapSet.new())
    sweep(&Wellness.water_reminders_due/2, &water/3, now, MapSet.new())
  end

  defp sweep(due_fun, handle, now, seen) do
    case now |> due_fun.(@batch) |> Enum.reject(&MapSet.member?(seen, &1)) do
      [] ->
        :ok

      due ->
        Enum.each(due, fn {user_id, key} -> handle.(user_id, key, now) end)
        sweep(due_fun, handle, now, MapSet.union(seen, MapSet.new(due)))
    end
  end

  @doc "One craving's «Πώς πήγε;», when still due (public for tests)."
  def follow_up(user_id, craving_id, now) do
    context = %{user_id: user_id}

    Wellness.with_context(context, fn ->
      craving = Wellness.get_craving(craving_id, user_id)

      cond do
        not NudgePolicy.follow_up_due?(craving, now) ->
          :ok

        not section_on?(context, user_id, "cravings") ->
          {:ok, _craving} = Wellness.mark_followed_up(craving, now)
          :ok

        true ->
          {:ok, _craving} = Wellness.mark_followed_up(craving, now)

          Notifications.dispatch_event(:craving_follow_up, %{
            user_id: user_id,
            craving_id: craving.id,
            dedupe_key: NudgePolicy.follow_up_dedupe_key(craving.id)
          })
      end
    end)
  rescue
    error -> failed("craving follow-up", user_id, error)
  end

  @doc "One person's afternoon water reminder for their local `day` (public for tests)."
  def water(user_id, %Date{} = day, _now) do
    context = %{user_id: user_id}

    Wellness.with_context(context, fn ->
      prefs = Wellness.preferences(user_id)
      entries = Wellness.list_entries(user_id, day, day)

      if NudgePolicy.water_behind?(prefs, day, entries) and
           section_on?(context, user_id, "wellness") do
        :ok = Wellness.mark_water_reminded(user_id, day)

        Notifications.dispatch_event(:water_reminder, %{
          user_id: user_id,
          dedupe_key: NudgePolicy.water_dedupe_key(user_id, day)
        })
      else
        :ok
      end
    end)
  rescue
    error -> failed("water reminder", user_id, error)
  end

  defp section_on?(context, user_id, section),
    do: context |> Body.settings(user_id) |> Body.section_on?(section)

  defp failed(what, user_id, error) do
    Logger.error("#{what} #{user_id} failed: #{Exception.message(error)}")
    :error
  end
end
