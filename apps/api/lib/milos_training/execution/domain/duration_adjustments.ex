defmodule MilosTraining.Execution.Domain.DurationAdjustments do
  @moduledoc """
  Mid-workout clock changes ("+30 s" / "−30 s" from the pause sheet).

  Clients send `%{segment_key => delta_seconds}`. The stored form is enriched
  with what the coach needs to read it later without rebuilding the timer
  sequence:

      %{"segment:3" => %{"delta_seconds" => 120, "authored_seconds" => 720,
                         "section_id" => "…", "section_name" => "AMRAP 12",
                         "label" => "AMRAP 12"}}

  Only countdowns and capped count-ups can be adjusted. Adjustments that no
  longer match the sequence (the workout changed) are dropped rather than
  rejected, so a device can never get stuck re-sending them.
  """

  @max_delta_seconds 3_600
  @min_seconds 5

  def max_delta_seconds, do: @max_delta_seconds
  def min_seconds, do: @min_seconds

  @doc "Validates and enriches client adjustments against the timer sequence."
  def normalize(nil, _segments, existing), do: existing || %{}

  def normalize(incoming, segments, _existing) when is_map(incoming) and is_list(segments) do
    by_key = Map.new(segments, &{to_string(value(&1, :segment_key)), &1})

    Enum.reduce(incoming, %{}, fn {key, raw}, acc ->
      key = to_string(key)

      with %{} = segment <- Map.get(by_key, key),
           authored when is_integer(authored) and authored > 0 <- adjustable_seconds(segment),
           delta when is_integer(delta) and delta != 0 <- clamp(delta(raw), authored) do
        Map.put(acc, key, %{
          "delta_seconds" => delta,
          "authored_seconds" => authored,
          "section_id" => to_string(value(segment, :section_id)),
          "section_name" => value(segment, :section_name),
          "label" => value(segment, :label)
        })
      else
        _ -> acc
      end
    end)
  end

  def normalize(_incoming, _segments, existing), do: existing || %{}

  @doc "Applies stored adjustments to a timer sequence."
  def apply_to(segments, adjustments) when is_list(segments) and is_map(adjustments) do
    Enum.map(segments, fn segment ->
      key = to_string(value(segment, :segment_key))

      case {Map.get(adjustments, key), adjustable_seconds(segment)} do
        {nil, _} ->
          segment

        {_adjustment, nil} ->
          segment

        {adjustment, authored} ->
          Map.put(
            segment,
            :duration_seconds,
            max(@min_seconds, authored + (delta(adjustment) || 0))
          )
      end
    end)
  end

  def apply_to(segments, _adjustments), do: segments

  defp adjustable_seconds(segment) do
    kind = to_string(value(segment, :kind))
    seconds = value(segment, :duration_seconds)

    if kind in ["countdown", "countup"] and is_integer(seconds) and seconds > 0, do: seconds
  end

  defp delta(value) when is_integer(value), do: value
  defp delta(value) when is_float(value), do: round(value)
  defp delta(%{} = map), do: delta(Map.get(map, "delta_seconds", Map.get(map, :delta_seconds)))
  defp delta(_value), do: nil

  defp clamp(nil, _authored), do: nil

  defp clamp(delta, authored) do
    delta
    |> min(@max_delta_seconds)
    |> max(-@max_delta_seconds)
    |> max(@min_seconds - authored)
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
