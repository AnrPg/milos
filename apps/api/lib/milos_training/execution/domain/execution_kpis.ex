defmodule MilosTraining.Execution.Domain.ExecutionKpis do
  @moduledoc """
  Execution health KPIs (workout execution audit, §1.3).

  Most KPIs derive from the execution record itself (status, position,
  scores). The rest only the athlete's device can observe, so progress and
  completion payloads carry `kpi_counters`:

    - `skips` / `countdown_skips` — segments ended early with "Next"/"Skip",
      overall and among countdown segments
    - `countdown_segments` — countdown segments left by any means
    - `pauses` / `paused_ms` — pause count and total paused time
    - `finish_wizard_opens` — times the review screen was opened
    - `first_started_at_ms` — epoch ms of the first tap on Start; stored as
      `first_start_delay_ms` relative to the execution's start

  Counters only grow: a stale or replayed snapshot can never lower them.
  """

  @counter_keys ~w(skips countdown_skips countdown_segments pauses paused_ms finish_wizard_opens)
  @max_counter 1_000_000_000

  @doc "Merges client counters into the stored ones, dropping unknown or invalid keys."
  def merge_counters(existing, incoming, started_at_utc \\ nil)

  def merge_counters(existing, incoming, started_at_utc) when is_map(incoming) do
    existing = stringify(existing || %{})
    incoming = stringify(incoming)

    counters =
      Enum.reduce(@counter_keys, Map.take(existing, @counter_keys), fn key, acc ->
        case counter(incoming[key]) do
          nil -> acc
          value -> Map.put(acc, key, max(value, counter(acc[key]) || 0))
        end
      end)

    case {existing["first_start_delay_ms"],
          first_start_delay(incoming["first_started_at_ms"], started_at_utc)} do
      {delay, _new} when is_integer(delay) -> Map.put(counters, "first_start_delay_ms", delay)
      {_none, delay} when is_integer(delay) -> Map.put(counters, "first_start_delay_ms", delay)
      _ -> counters
    end
  end

  def merge_counters(existing, _incoming, _started_at_utc), do: stringify(existing || %{})

  defp counter(value) when is_integer(value) and value >= 0, do: min(value, @max_counter)
  defp counter(_value), do: nil

  defp first_start_delay(epoch_ms, %DateTime{} = started_at) when is_integer(epoch_ms) do
    delay = epoch_ms - DateTime.to_unix(started_at, :millisecond)
    # Ignore clocks that are obviously wrong (negative or more than a day).
    if delay >= 0 and delay <= 86_400_000, do: delay
  end

  defp first_start_delay(_epoch_ms, _started_at), do: nil

  @doc """
  Summarizes executions (maps with `:status`, `:current_segment_index`,
  `:section_scores`, `:kpi_counters` and `:started_at_utc`) into the KPI report.
  """
  def summarize(executions) do
    started = length(executions)
    {completed, open} = Enum.split_with(executions, &(to_string(&1.status) == "completed"))
    counters = Enum.map(executions, &stringify(&1.kpi_counters || %{}))
    sum = fn key -> Enum.reduce(counters, 0, &(&2 + (&1[key] || 0))) end
    scored = Enum.filter(completed, &(&1.section_scores not in [nil, []]))
    wizard_opens = sum.("finish_wizard_opens")

    %{
      started: started,
      completed: length(completed),
      completion_rate: ratio(length(completed), started),
      abandon_points: abandon_points(open),
      score_capture_rate: ratio(Enum.count(scored, &manual_score?/1), length(scored)),
      skip_rate_on_countdowns: ratio(sum.("countdown_skips"), sum.("countdown_segments")),
      skips: sum.("skips"),
      pauses_per_execution: ratio(sum.("pauses"), started),
      average_paused_ms: if(started > 0, do: div(sum.("paused_ms"), started), else: nil),
      median_time_to_first_start_ms:
        counters
        |> Enum.map(& &1["first_start_delay_ms"])
        |> Enum.filter(&is_integer/1)
        |> median(),
      finish_wizard_drop_off_rate:
        if(wizard_opens > 0, do: ratio(max(wizard_opens - length(completed), 0), wizard_opens))
    }
  end

  # Where unfinished executions stopped, most common first.
  defp abandon_points(open) do
    open
    |> Enum.frequencies_by(& &1.current_segment_index)
    |> Enum.sort_by(fn {index, count} -> {-count, index} end)
    |> Enum.take(10)
    |> Enum.map(fn {index, count} -> %{segment_index: index, count: count} end)
  end

  defp manual_score?(execution) do
    Enum.any?(execution.section_scores, fn score ->
      score = stringify(score)
      score["source"] == "manual" or score["kind"] == "final"
    end)
  end

  defp ratio(_part, 0), do: nil
  defp ratio(part, whole), do: Float.round(part / whole, 4)

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1,
      do: Enum.at(sorted, middle),
      else: div(Enum.at(sorted, middle - 1) + Enum.at(sorted, middle), 2)
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
