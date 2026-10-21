defmodule Palee.Execution.Domain.ExecutionKpis do
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

  The server also records, from the timer sequence it validates against:

    - `position` — where the athlete is (format, section, segment index and
      elapsed time), so unfinished executions show where people stop
    - `formats` — every timer format in the workout, for per-format rates

  Free-text workouts have no sequence; they report the format `free_text`.
  """

  @counter_keys ~w(skips countdown_skips countdown_segments pauses paused_ms finish_wizard_opens)
  @max_counter 1_000_000_000

  @doc "Merges client counters into the stored ones, dropping unknown or invalid keys."
  def merge_counters(existing, incoming, started_at_utc \\ nil)

  def merge_counters(existing, incoming, started_at_utc) when is_map(incoming) do
    existing = stringify(existing || %{})
    incoming = stringify(incoming)

    counters =
      Enum.reduce(
        @counter_keys,
        Map.take(existing, @counter_keys ++ ["position", "formats"]),
        fn key, acc ->
          case counter(incoming[key]) do
            nil -> acc
            value -> Map.put(acc, key, max(value, counter(acc[key]) || 0))
          end
        end
      )

    case {existing["first_start_delay_ms"],
          first_start_delay(incoming["first_started_at_ms"], started_at_utc)} do
      {delay, _new} when is_integer(delay) -> Map.put(counters, "first_start_delay_ms", delay)
      {_none, delay} when is_integer(delay) -> Map.put(counters, "first_start_delay_ms", delay)
      _ -> counters
    end
  end

  def merge_counters(existing, _incoming, _started_at_utc), do: stringify(existing || %{})

  @doc "Records where the athlete is in the sequence (and which formats it has)."
  def put_position(counters, segments, index, total_elapsed_ms) when is_list(segments) do
    segment = Enum.at(segments, index || 0)

    position = %{
      "format" => if(segment, do: to_string(value(segment, :format)), else: "free_text"),
      "section_name" => segment && value(segment, :section_name),
      "segment_index" => index || 0,
      "segment_count" => length(segments),
      "elapsed_ms" => if(is_integer(total_elapsed_ms), do: total_elapsed_ms, else: 0)
    }

    formats =
      case segments do
        [] -> ["free_text"]
        _ -> segments |> Enum.map(&to_string(value(&1, :format))) |> Enum.uniq()
      end

    counters
    |> Map.put("position", position)
    |> Map.put_new("formats", formats)
  end

  def put_position(counters, _segments, _index, _total), do: counters

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp counter(value) when is_integer(value) and value >= 0, do: min(value, @max_counter)
  defp counter(_value), do: nil

  defp first_start_delay(epoch_ms, %DateTime{} = started_at) when is_integer(epoch_ms) do
    delay = epoch_ms - DateTime.to_unix(started_at, :millisecond)
    # Ignore clocks that are obviously wrong (negative or more than a day).
    if delay >= 0 and delay <= 86_400_000, do: delay
  end

  defp first_start_delay(_epoch_ms, _started_at), do: nil

  @doc """
  Summarizes executions into the KPI report. Each row is a map with
  `:status`, `:source`, `:current_segment_index`, `:section_scores`,
  `:kpi_counters`, `:duration_adjustments`, `:total_elapsed_ms` and
  `:started_at_utc`.
  """
  def summarize(executions) do
    rows = Enum.map(executions, &row/1)
    started = length(rows)
    {completed, open} = Enum.split_with(rows, & &1.completed?)
    sum = fn key -> Enum.reduce(rows, 0, &(&2 + (&1.counters[key] || 0))) end
    scored = Enum.filter(completed, &(&1.scores != []))
    wizard_opens = sum.("finish_wizard_opens")
    {free_text, structured} = Enum.split_with(rows, &("free_text" in &1.formats))

    %{
      started: started,
      completed: length(completed),
      completion_rate: ratio(length(completed), started),
      abandon_points: abandon_points(open),
      abandon_by_format: abandon_by_format(open),
      by_format: rates_by(rows, & &1.formats),
      by_source: rates_by(rows, &[&1.source]),
      structured: %{
        started: length(structured),
        completed: Enum.count(structured, & &1.completed?)
      },
      free_text: free_text_summary(free_text),
      daily: daily(rows),
      score_capture_rate: ratio(Enum.count(scored, &manual_score?/1), length(scored)),
      skip_rate_on_countdowns: ratio(sum.("countdown_skips"), sum.("countdown_segments")),
      skips: sum.("skips"),
      pauses_per_execution: ratio(sum.("pauses"), started),
      average_paused_ms: if(started > 0, do: div(sum.("paused_ms"), started), else: nil),
      median_time_to_first_start_ms:
        rows
        |> Enum.map(& &1.counters["first_start_delay_ms"])
        |> Enum.filter(&is_integer/1)
        |> median(),
      median_completed_duration_ms:
        completed |> Enum.map(& &1.elapsed_ms) |> Enum.filter(&(&1 > 0)) |> median(),
      clock_adjustment_rate: ratio(Enum.count(rows, & &1.adjusted?), started),
      finish_wizard_drop_off_rate:
        if(wizard_opens > 0, do: ratio(max(wizard_opens - length(completed), 0), wizard_opens))
    }
  end

  defp row(execution) do
    counters = stringify(field(execution, :kpi_counters) || %{})
    position = counters["position"] || %{}

    %{
      completed?: to_string(field(execution, :status)) == "completed",
      source: to_string(field(execution, :source) || "unknown"),
      index: field(execution, :current_segment_index) || 0,
      scores: field(execution, :section_scores) || [],
      counters: counters,
      position: position,
      formats: List.wrap(counters["formats"] || position["format"] || "unknown"),
      adjusted?: (field(execution, :duration_adjustments) || %{}) != %{},
      elapsed_ms: field(execution, :total_elapsed_ms) || 0,
      date: date(field(execution, :started_at_utc))
    }
  end

  # Where unfinished executions stopped, most common first.
  defp abandon_points(open) do
    open
    |> Enum.frequencies_by(fn row ->
      {row.position["format"] || "unknown", row.position["section_name"], row.index}
    end)
    |> Enum.sort_by(fn {{format, _name, index}, count} -> {-count, format, index} end)
    |> Enum.take(10)
    |> Enum.map(fn {{format, name, index}, count} ->
      %{format: format, section_name: name, segment_index: index, count: count}
    end)
  end

  defp abandon_by_format(open) do
    total = length(open)

    open
    |> Enum.frequencies_by(&(&1.position["format"] || "unknown"))
    |> Enum.sort_by(fn {format, count} -> {-count, format} end)
    |> Enum.map(fn {format, count} ->
      %{format: format, count: count, share: ratio(count, total)}
    end)
  end

  defp rates_by(rows, keys_fun) do
    rows
    |> Enum.flat_map(fn row -> Enum.map(keys_fun.(row), &{&1, row.completed?}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {key, outcomes} ->
      done = Enum.count(outcomes, & &1)

      %{
        key: key,
        started: length(outcomes),
        completed: done,
        completion_rate: ratio(done, length(outcomes))
      }
    end)
    |> Enum.sort_by(&{-&1.started, &1.key})
  end

  defp free_text_summary(rows) do
    abandoned = Enum.reject(rows, & &1.completed?)

    %{
      started: length(rows),
      completed: length(rows) - length(abandoned),
      completion_rate: ratio(length(rows) - length(abandoned), length(rows)),
      median_abandon_elapsed_ms:
        abandoned |> Enum.map(&(&1.position["elapsed_ms"] || &1.elapsed_ms)) |> median()
    }
  end

  defp daily(rows) do
    rows
    |> Enum.reject(&is_nil(&1.date))
    |> Enum.group_by(& &1.date)
    |> Enum.map(fn {date, day} ->
      %{date: date, started: length(day), completed: Enum.count(day, & &1.completed?)}
    end)
    |> Enum.sort_by(& &1.date)
  end

  defp date(%DateTime{} = value), do: value |> DateTime.to_date() |> Date.to_iso8601()
  defp date(%NaiveDateTime{} = value), do: value |> NaiveDateTime.to_date() |> Date.to_iso8601()
  defp date(_value), do: nil

  defp manual_score?(row) do
    Enum.any?(row.scores, fn score ->
      score = stringify(score)
      score["source"] == "manual" or score["kind"] == "final"
    end)
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

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
