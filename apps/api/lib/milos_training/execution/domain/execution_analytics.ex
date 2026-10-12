defmodule MilosTraining.Execution.Domain.ExecutionAnalytics do
  @moduledoc """
  Pure derivation of execution analytics facts (ADR-113), from an execution
  snapshot and its timer segments (`TimerSequenceBuilder.build/1`).

  These are the server-observable halves of the timer audit's §1.3 KPIs:
  completion facts (duration, score capture) and the abandon point (format
  and segment index at the last progress update). Facts the server cannot
  observe - pauses, manual skips, round taps - come from the client
  interaction ingestion instead.
  """

  @doc """
  Completion facts. A section counts as manually scored when its final
  `section_scores` entry did not come from the automatic snapshotter
  (`source != "auto"`); that is the audit's "score capture rate" numerator.
  """
  def completion_facts(execution, segments) when is_list(segments) do
    scoreable = scoreable_section_ids(segments)
    scores = value(execution, :section_scores) || []

    manual =
      scores
      |> Enum.filter(&(to_string(value(&1, :source)) != "auto"))
      |> section_ids_in(scoreable)

    auto =
      scores
      |> Enum.filter(&(to_string(value(&1, :source)) == "auto"))
      |> section_ids_in(scoreable)
      |> MapSet.difference(manual)

    %{
      duration_ms:
        duration_ms(value(execution, :started_at_utc), value(execution, :completed_at_utc)),
      total_elapsed_ms: value(execution, :total_elapsed_ms),
      segment_count: length(segments),
      section_count: segments |> section_ids() |> MapSet.size(),
      scoreable_section_count: MapSet.size(scoreable),
      manually_scored_section_count: MapSet.size(manual),
      auto_scored_section_count: MapSet.size(auto),
      checked_exercise_count: length(value(execution, :checked_exercise_ids) || []),
      primary_format: primary_format(segments)
    }
  end

  @doc """
  Abandon point for a started, never-completed execution: the segment index,
  format and kind of the last persisted progress snapshot, plus how far into
  the workout that is and how long ago progress last moved.
  """
  def abandonment_facts(execution, segments, %DateTime{} = now) when is_list(segments) do
    index = value(execution, :current_segment_index) || 0
    segment = Enum.at(segments, index)
    started_at = value(execution, :started_at_utc)
    last_progress_at = value(execution, :last_progress_at)

    %{
      abandon_segment_index: index,
      abandon_format: segment && to_string(value(segment, :format)),
      abandon_segment_kind: segment && to_string(value(segment, :kind)),
      segment_count: length(segments),
      abandon_progress_pct: progress_pct(index, length(segments)),
      total_elapsed_ms: value(execution, :total_elapsed_ms),
      checked_exercise_count: length(value(execution, :checked_exercise_ids) || []),
      hours_since_start: started_at && div(DateTime.diff(now, started_at, :second), 3_600),
      had_progress_update: not is_nil(last_progress_at),
      minutes_since_last_progress:
        last_progress_at && div(DateTime.diff(now, last_progress_at, :second), 60)
    }
  end

  @doc """
  Whether a started execution counts as abandoned at `now`: not completed and
  started at least `threshold_hours` ago.
  """
  def abandoned?(execution, %DateTime{} = now, threshold_hours)
      when is_integer(threshold_hours) and threshold_hours > 0 do
    started_at = value(execution, :started_at_utc)

    is_nil(value(execution, :completed_at_utc)) and not is_nil(started_at) and
      DateTime.diff(now, started_at, :second) >= threshold_hours * 3_600
  end

  defp scoreable_section_ids(segments) do
    segments
    |> Enum.filter(&(value(&1, :scoreable) == true))
    |> section_ids()
  end

  defp section_ids(segments) do
    segments
    |> Enum.map(&value(&1, :section_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> MapSet.new()
  end

  defp section_ids_in(scores, scoreable) do
    scores
    |> Enum.map(&value(&1, :section_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> MapSet.new()
    |> MapSet.intersection(scoreable)
  end

  defp primary_format([]), do: nil
  defp primary_format([first | _rest]), do: first |> value(:format) |> to_string()

  defp duration_ms(%DateTime{} = started, %DateTime{} = completed),
    do: max(DateTime.diff(completed, started, :millisecond), 0)

  defp duration_ms(_started, _completed), do: nil

  defp progress_pct(_index, 0), do: nil
  defp progress_pct(index, count), do: min(div(index * 100, count), 100)

  defp value(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key))
      found -> found
    end
  end
end
