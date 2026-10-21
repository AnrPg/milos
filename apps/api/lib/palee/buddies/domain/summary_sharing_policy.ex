defmodule Palee.Buddies.Domain.SummarySharingPolicy do
  @moduledoc """
  The coach's weekly wellness summary (ADR-160 §4; M11 board answer). A
  coach sees nothing of a member's wellness unless the member turns on
  «Ευεξία · εβδομαδιαία σύνοψη» in Κοινοποίηση & ορατότητα: counts only
  (nights at their sleep goal, water days on goal, days with meals
  logged). Cravings appear only with the second toggle «Λιγούρες στη
  σύνοψη», and then as a count and the times they happened; never notes,
  causes, intensity or outcomes. Each toggle is a grant record; turning one
  off withdraws it, and turning the summary off withdraws both.
  """

  @scopes ~w(wellness cravings)

  def scopes, do: @scopes

  @doc "The member's toggles from their active grants."
  def toggles(grants) do
    active = grants |> Enum.filter(&is_nil(&1.withdrawn_at)) |> Map.new(&{&1.scope, &1})
    wellness = Map.get(active, "wellness")
    cravings = wellness && Map.get(active, "cravings")

    %{
      wellness: not is_nil(wellness),
      cravings: not is_nil(cravings),
      wellness_since: wellness && wellness.granted_at,
      cravings_since: cravings && cravings.granted_at
    }
  end

  @doc """
  What to grant and withdraw for `params` (`wellness`, `cravings`
  booleans; a missing one keeps its state) over the current `toggles`.
  Cravings need the summary on.
  """
  def changes(toggles, params) do
    with {:ok, wellness} <- flag(params, "wellness", toggles.wellness),
         {:ok, cravings} <- flag(params, "cravings", toggles.cravings) do
      asked_cravings? = Map.get(params, "cravings", Map.get(params, :cravings)) == true

      if asked_cravings? and not wellness do
        {:error, :summary_required}
      else
        wanted = %{"wellness" => wellness, "cravings" => wellness and cravings}
        current = %{"wellness" => toggles.wellness, "cravings" => toggles.cravings}

        {:ok,
         %{
           grant: for({scope, true} <- wanted, not current[scope], do: scope),
           withdraw: for({scope, false} <- wanted, current[scope], do: scope)
         }}
      end
    end
  end

  defp flag(params, key, current) do
    case Map.get(params, key, Map.get(params, String.to_atom(key), :missing)) do
      :missing -> {:ok, current}
      value when is_boolean(value) -> {:ok, value}
      _other -> {:error, :invalid_summary_sharing}
    end
  end

  @doc """
  The coach's view of one week. `week` is M11's week line
  (`Wellness.week_line/1`); `cravings` the week's cravings, read only for
  when they happened, and only when the member allowed it.
  """
  def coach_summary({from, to}, toggles, week, cravings) do
    %{
      week_start: from,
      week_end: to,
      allowed_since: toggles.wellness_since,
      sleep: %{nights_on_goal: week.nights_on_goal, nights_logged: week.nights_logged},
      water: %{days_on_goal: week.water_days_on_goal, days_logged: week.water_days_logged},
      meals: %{days_logged: week.meal_days_logged},
      cravings: if(toggles.cravings, do: craving_times(cravings), else: nil)
    }
  end

  defp craving_times(cravings) do
    %{
      count: length(cravings),
      moments:
        Enum.map(cravings, fn craving ->
          %{date: craving.occurred_on, time: local_time(craving.occurred_at, craving.occurred_tz)}
        end)
    }
  end

  defp local_time(at, tz) do
    local =
      case DateTime.shift_zone(at, tz || "Etc/UTC") do
        {:ok, local} -> local
        {:error, _reason} -> at
      end

    local |> DateTime.to_time() |> Time.to_iso8601() |> String.slice(0, 5)
  end
end
