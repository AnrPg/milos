defmodule MilosTraining.Execution.Domain.ProgressValidator do
  @moduledoc """
  Validates a client progress snapshot against the immutable materialized timer
  sequence. This is intentionally pure so every transport can enforce the same
  semantic contract.
  """

  @max_elapsed_ms 2_592_000_000
  @max_cycles 1_000_000
  @max_checked_steps 10_000

  def validate(progress, segments, previous) when is_map(progress) and is_list(segments) do
    allowed_steps = allowed_step_ids(segments)
    section_ids = segments |> Enum.map(&value(&1, :section_id)) |> MapSet.new()
    segment_keys = segments |> Enum.map(&value(&1, :segment_key)) |> MapSet.new()

    with :ok <- validate_index(progress.current_segment_index, segments),
         :ok <- validate_checked(progress.checked_exercise_ids, allowed_steps),
         :ok <- validate_elapsed(progress.paused_elapsed_ms),
         :ok <- validate_elapsed(progress.total_elapsed_ms),
         :ok <- validate_map(progress.section_elapsed_ms, section_ids, @max_elapsed_ms),
         :ok <- validate_map(progress.segment_cycle_counts, segment_keys, @max_cycles),
         :ok <- validate_scores(value(progress, :section_scores, []), section_ids),
         :ok <- validate_monotonic(progress, previous) do
      :ok
    else
      _ -> {:error, :bad_request}
    end
  end

  def validate(_progress, _segments, _previous), do: {:error, :bad_request}

  defp validate_index(0, []), do: :ok

  defp validate_index(index, segments)
       when is_integer(index) and index >= 0 and index < length(segments),
       do: :ok

  defp validate_index(_index, _segments), do: :error

  defp validate_checked(ids, allowed) when is_list(ids) and length(ids) <= @max_checked_steps do
    if Enum.all?(ids, &(is_binary(&1) and MapSet.member?(allowed, &1))), do: :ok, else: :error
  end

  defp validate_checked(_ids, _allowed), do: :error

  defp validate_elapsed(value)
       when is_integer(value) and value >= 0 and value <= @max_elapsed_ms,
       do: :ok

  defp validate_elapsed(_value), do: :error

  defp validate_map(values, allowed_keys, maximum) when is_map(values) do
    if map_size(values) <= MapSet.size(allowed_keys) and
         Enum.all?(values, fn {key, value} ->
           MapSet.member?(allowed_keys, to_string(key)) and is_integer(value) and value >= 0 and
             value <= maximum
         end) do
      :ok
    else
      :error
    end
  end

  defp validate_map(_values, _allowed_keys, _maximum), do: :error

  defp validate_scores(scores, section_ids) when is_list(scores) do
    ids = Enum.map(scores, &value(&1, :section_id))

    if length(scores) <= MapSet.size(section_ids) and length(ids) == length(Enum.uniq(ids)) and
         Enum.all?(scores, fn score ->
           MapSet.member?(section_ids, value(score, :section_id)) and
             valid_score_value?(value(score, :value)) and
             valid_optional_string?(value(score, :unit), 32) and
             valid_optional_string?(value(score, :score_type), 32) and
             valid_optional_string?(value(score, :source), 16) and
             valid_optional_string?(value(score, :kind), 16)
         end) do
      :ok
    else
      :error
    end
  end

  defp validate_scores(_scores, _section_ids), do: :error

  defp valid_score_value?(value) when is_number(value),
    do: value >= -1_000_000_000 and value <= 1_000_000_000

  defp valid_score_value?(value) when is_binary(value), do: byte_size(value) in 1..100
  defp valid_score_value?(_value), do: false

  defp valid_optional_string?(nil, _maximum), do: true

  defp valid_optional_string?(value, maximum),
    do: is_binary(value) and byte_size(value) <= maximum

  defp validate_monotonic(progress, previous) do
    previous_total = previous[:total_elapsed_ms] || previous["total_elapsed_ms"] || 0
    previous_sections = previous[:section_elapsed_ms] || previous["section_elapsed_ms"] || %{}
    previous_cycles = previous[:segment_cycle_counts] || previous["segment_cycle_counts"] || %{}

    if progress.total_elapsed_ms >= previous_total and
         map_does_not_regress?(progress.section_elapsed_ms, previous_sections) and
         map_does_not_regress?(progress.segment_cycle_counts, previous_cycles) do
      :ok
    else
      :error
    end
  end

  defp map_does_not_regress?(current, previous) do
    Enum.all?(previous, fn {key, old_value} ->
      Map.get(current, to_string(key), 0) >= old_value
    end)
  end

  defp allowed_step_ids(segments) do
    segments
    |> Enum.flat_map(fn segment ->
      segment_key = value(segment, :segment_key)

      segment
      |> value(:exercises, [])
      |> Enum.reject(&value(&1, :excluded, false))
      |> Enum.flat_map(fn exercise ->
        exercise_id = value(exercise, :id)
        sets = max(value(exercise, :sets, 1) || 1, 1)

        if sets == 1 do
          ["#{segment_key}::#{exercise_id}"]
        else
          Enum.map(1..sets, &"#{segment_key}::#{exercise_id}::set:#{&1}")
        end
      end)
    end)
    |> MapSet.new()
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
