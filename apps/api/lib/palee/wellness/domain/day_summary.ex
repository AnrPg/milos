defmodule Palee.Wellness.Domain.DaySummary do
  @moduledoc """
  The «Σήμερα» card and the week strip (ADR-159 §2): per local day, what the
  member logged, measured against their own targets only. Each item gets a
  neutral status — `full` (on your target), `partial` (something logged) or
  `none` — and cravings are a count, never a grade.
  """

  alias Palee.Nutrition.Domain.PortionPolicy
  alias Palee.Wellness.Domain.{Meal, Sleep, Water}

  @doc """
  One summary per date in `dates`. `entries` and `cravings` are the member's
  live rows of the window; `moods` maps a date to the latest Πώς νιώθω
  answers of that day; `prefs` holds the targets.
  """
  def build(dates, entries, cravings, moods, prefs) do
    entries = Enum.group_by(entries, & &1.occurred_on)
    cravings = Enum.group_by(cravings, & &1.occurred_on)

    Enum.map(dates, fn date ->
      day(
        date,
        Map.get(entries, date, []),
        Map.get(cravings, date, []),
        Map.get(moods, date),
        prefs
      )
    end)
  end

  defp day(date, entries, cravings, mood, prefs) do
    by_kind = Enum.group_by(entries, & &1.kind)

    water = water(Map.get(by_kind, "water", []), prefs)
    sleep = sleep(Map.get(by_kind, "sleep", []), prefs)
    meals = meals(Map.get(by_kind, "meal", []))

    %{
      date: date,
      water: water,
      sleep: sleep,
      meals: meals,
      cravings: %{count: length(cravings), status: if(cravings == [], do: "none", else: "logged")},
      mood: mood
    }
  end

  defp water(entries, prefs) do
    ml = entries |> Enum.map(&Water.ml(&1.value)) |> Enum.sum()

    %{
      ml: ml,
      goal_ml: prefs.water_goal_ml,
      glass_ml: prefs.glass_ml,
      count: length(entries),
      status: status(ml, prefs.water_goal_ml)
    }
  end

  # The night is the longest non-nap sleep of the day; naps add to the total.
  defp sleep(entries, prefs) do
    {naps, nights} = Enum.split_with(entries, &Sleep.nap?(&1.value))
    night = Enum.max_by(nights, &(Sleep.minutes(&1.value) || 0), fn -> nil end)
    minutes = night && Sleep.minutes(night.value)

    %{
      entry_id: night && night.id,
      minutes: minutes,
      quality: night && night.value["quality"],
      source: night && night.source,
      nap_minutes: naps |> Enum.map(&(Sleep.minutes(&1.value) || 0)) |> Enum.sum(),
      goal_minutes: prefs.sleep_goal_minutes,
      status:
        cond do
          is_nil(night) -> "none"
          is_integer(minutes) -> status(minutes, prefs.sleep_goal_minutes)
          true -> "partial"
        end
    }
  end

  # Logging, not eating, is what the strip reflects: full when the three main
  # meals are logged, whatever was eaten (§8.6).
  defp meals(entries) do
    slots = entries |> Enum.map(& &1.value["slot"]) |> MapSet.new()
    logged_main = Enum.count(Meal.main_slots(), &MapSet.member?(slots, &1))

    %{
      count: length(entries),
      portions: PortionPolicy.logged(Enum.map(entries, & &1.value)),
      status:
        cond do
          entries == [] -> "none"
          logged_main == length(Meal.main_slots()) or length(entries) >= 3 -> "full"
          true -> "partial"
        end
    }
  end

  defp status(0, _goal), do: "none"
  defp status(amount, goal) when amount >= goal, do: "full"
  defp status(_amount, _goal), do: "partial"

  @doc "The plain line under the week strip: counts against your own targets."
  def week_line(days) do
    nights = Enum.filter(days, &is_integer(&1.sleep.minutes))

    %{
      nights_logged: length(nights),
      nights_on_goal: Enum.count(nights, &(&1.sleep.status == "full")),
      water_days_logged: Enum.count(days, &(&1.water.ml > 0)),
      water_days_on_goal: Enum.count(days, &(&1.water.status == "full")),
      meal_days_logged: Enum.count(days, &(&1.meals.count > 0)),
      cravings: days |> Enum.map(& &1.cravings.count) |> Enum.sum()
    }
  end
end
