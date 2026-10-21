defmodule MilosTraining.Application.WidgetSnapshots do
  @moduledoc """
  What the home-screen widgets read and do (ADR-173), as the person behind a
  widget token (`WidgetAccess`):

    * `show/2` (`GET /api/widget/snapshot`): water today, the first items of
      «Σήμερα» across providers and the next booked class
      (`Widgets.Domain.WidgetSnapshot`);
    * `add_water/2` (`POST /api/widget/water`): «+1 νερό», one glass of the
      member's own size through the same path as Ευεξία (consent, local
      day, private), then the new snapshot.

  `timezone` (IANA, default UTC) is the phone's zone: it decides "today".
  """

  alias MilosTraining.Application.{GetMyWellness, LogWellnessEntry, MyToday}
  alias MilosTraining.Wellness
  alias MilosTraining.Widgets.Domain.WidgetSnapshot

  def show(context, params, now \\ DateTime.utc_now()) do
    with {:ok, zone} <- zone(params),
         {:ok, today} <- MyToday.call(context, %{"timezone" => zone}, now),
         {:ok, wellness} <- wellness_today(context, zone, now) do
      {:ok,
       WidgetSnapshot.build(
         %{items: today.items, water: water(wellness), consented: wellness.consented},
         now
       )}
    end
  end

  def add_water(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with {:ok, zone} <- zone(params),
         glass_ml =
           Wellness.with_context(context, fn -> Wellness.preferences(user_id) end).glass_ml,
         {:ok, _entry} <-
           LogWellnessEntry.call(
             context,
             %{"kind" => "water", "value" => %{"ml" => glass_ml}, "occurred_tz" => zone},
             now
           ) do
      show(context, params, now)
    end
  end

  defp wellness_today(context, zone, now) do
    {:ok, day} = Wellness.local_day(now, zone)
    GetMyWellness.call(context, %{"from" => Date.to_iso8601(day), "to" => Date.to_iso8601(day)})
  end

  defp water(%{preferences: preferences, days: [day | _]}) do
    if "water" in (preferences.hidden_items || []), do: nil, else: day.water
  end

  defp water(_wellness), do: nil

  defp zone(params) do
    zone =
      case Map.get(params, :timezone, Map.get(params, "timezone")) do
        value when is_binary(value) and value != "" -> value
        _none -> "Etc/UTC"
      end

    if Wellness.valid_zone?(zone), do: {:ok, zone}, else: {:error, :invalid_timezone}
  end
end
