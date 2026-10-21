defmodule Palee.Analytics.Domain.TrainingLoad do
  @moduledoc """
  Training load as an indicator (ADR-165, vision §7.7 and §8.6). Pure.

  ## Session load
  A session's load is its session RPE: perceived effort (1-10) × minutes.
  Only sessions with both count; the others are counted as `unrated` and
  never estimated.

  ## Acute and chronic
  - acute: the load of the last 7 days, today included;
  - chronic: the weekly average of the last 28 days, today included;
  - ratio: acute ÷ chronic, two decimals.

  The ratio is given only when there is enough history: rated sessions in at
  least `@min_weeks_with_load` of the four 7-day blocks of the chronic
  window. Without it, `ratio` and `band` are nil and `sufficient` is false.

  ## Band
  The ratio falls in one of four neutral bands: `below` (< 0.8), `steady`
  (0.8 to 1.3), `above` (1.3 to 1.5), `well_above` (> 1.5). The band
  describes this week against the athlete's own usual week. It is an
  indicator, never a verdict or medical advice; clients must say so.

  ## Weeks
  `weeks` is the load of the last `@weeks` calendar weeks (Monday first,
  oldest first), for a small chart.
  """

  @weeks 8
  @min_weeks_with_load 3

  @below 0.8
  @steady_to 1.3
  @above_to 1.5

  def bands, do: %{below: @below, steady_to: @steady_to, above_to: @above_to}
  def chart_weeks, do: @weeks

  @doc "The first day the load needs data from (the chart and the chronic window)."
  def window_start(%Date{} = today) do
    chart = Date.add(Date.beginning_of_week(today), -7 * (@weeks - 1))
    chronic = Date.add(today, -27)
    if Date.compare(chart, chronic) == :lt, do: chart, else: chronic
  end

  @doc """
  The load of `sessions` (`%{on: Date, rpe: integer | nil, minutes: number |
  nil}`) as of `today`.
  """
  def build(sessions, %Date{} = today) when is_list(sessions) do
    window = window_start(today)

    in_window =
      Enum.filter(
        sessions,
        &(Date.compare(&1.on, window) != :lt and Date.compare(&1.on, today) != :gt)
      )

    {rated, unrated} = Enum.split_with(in_window, &rated?/1)
    rated = Enum.map(rated, &Map.put(&1, :load, &1.rpe * &1.minutes))

    acute_from = Date.add(today, -6)
    chronic_from = Date.add(today, -27)
    acute = load_between(rated, acute_from, today)
    chronic_sessions = between(rated, chronic_from, today)
    chronic = sum(chronic_sessions) / 4

    blocks_with_load =
      chronic_sessions
      |> Enum.map(&div(Date.diff(today, &1.on), 7))
      |> Enum.uniq()
      |> length()

    sufficient = blocks_with_load >= @min_weeks_with_load and chronic > 0
    ratio = if sufficient, do: Float.round(acute / chronic, 2)

    %{
      acute: round0(acute),
      chronic: round0(chronic),
      ratio: ratio,
      band: band(ratio),
      sufficient: sufficient,
      rated_sessions: length(between(rated, chronic_from, today)),
      unrated_sessions: length(between(unrated, chronic_from, today)),
      weeks: weekly(rated, today)
    }
  end

  defp rated?(%{rpe: rpe, minutes: minutes})
       when is_integer(rpe) and rpe in 1..10 and is_number(minutes) and minutes > 0,
       do: true

  defp rated?(_session), do: false

  defp between(sessions, from, to),
    do:
      Enum.filter(
        sessions,
        &(Date.compare(&1.on, from) != :lt and Date.compare(&1.on, to) != :gt)
      )

  defp load_between(sessions, from, to), do: sessions |> between(from, to) |> sum()

  defp sum(sessions), do: sessions |> Enum.map(& &1.load) |> Enum.sum() |> Kernel.*(1.0)

  defp weekly(rated, today) do
    this_week = Date.beginning_of_week(today)

    for offset <- (@weeks - 1)..0//-1 do
      week_start = Date.add(this_week, -7 * offset)
      sessions = between(rated, week_start, Date.add(week_start, 6))
      %{week_start: week_start, load: round0(sum(sessions)), sessions: length(sessions)}
    end
  end

  defp band(nil), do: nil
  defp band(ratio) when ratio < @below, do: "below"
  defp band(ratio) when ratio <= @steady_to, do: "steady"
  defp band(ratio) when ratio <= @above_to, do: "above"
  defp band(_ratio), do: "well_above"

  defp round0(value), do: round(value)
end
