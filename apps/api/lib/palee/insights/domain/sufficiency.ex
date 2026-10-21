defmodule Palee.Insights.Domain.Sufficiency do
  @moduledoc """
  The data-sufficiency gate of insights (ADR-166, plan D4): nothing is shown
  before the data spans four weeks, and each rule adds its own minimum
  sample. Also places an instant in the member's day (local date and part
  of day), the way the journal shows it. Pure.
  """

  @min_days 28
  @max_weeks 12

  @parts ~w(morning afternoon evening night)

  def min_days, do: @min_days
  def min_weeks, do: div(@min_days, 7)
  def parts, do: @parts

  @doc "Whether the earliest of `dates` is at least four weeks before `today` (inclusive)."
  def enough_span?([], _today), do: false

  def enough_span?(dates, %Date{} = today),
    do: Date.diff(today, Enum.min(dates, Date)) + 1 >= @min_days

  @doc "Whole weeks from the earliest of `dates` to `today`, at most twelve."
  def weeks([], _today), do: 0

  def weeks(dates, %Date{} = today),
    do: min(@max_weeks, div(max(Date.diff(today, Enum.min(dates, Date)) + 1, 0), 7))

  @doc "`{local_date, hour}` of `at` in `tz` (UTC when the zone is unknown)."
  def local(%DateTime{} = at, tz) do
    local =
      case is_binary(tz) and DateTime.shift_zone(at, tz) do
        {:ok, shifted} -> shifted
        _unknown -> at
      end

    {DateTime.to_date(local), local.hour}
  end

  @doc "The part of the day of a local hour: 05–12, 12–17, 17–22, 22–05."
  def part(hour) when hour in 5..11, do: "morning"
  def part(hour) when hour in 12..16, do: "afternoon"
  def part(hour) when hour in 17..21, do: "evening"
  def part(_hour), do: "night"

  @doc "The local dates of the sessions in the window."
  def training_days(sessions) do
    sessions
    |> Enum.map(fn session -> session |> local_of() |> elem(0) end)
    |> MapSet.new()
  end

  def local_of(%{at: at} = session), do: local(at, Map.get(session, :tz))

  @doc "Nights with hours logged, by the day they count for (the wake-up day)."
  def nights(days) do
    for %{date: date, sleep: %{minutes: minutes}} <- days, is_integer(minutes), into: %{} do
      {date, minutes}
    end
  end

  def mean([]), do: nil
  def mean(values), do: Enum.sum(values) / length(values)
end
