defmodule MilosTraining.Execution.Domain.ProgressSnapshotter do
  @moduledoc """
  Pure execution scoring/progress inference from timer segments plus persisted
  client progress state.
  """

  @time_fallback_formats ~w(for_time kcal_target ladder_descending pyramid hrr)a

  def progress_snapshots(segments, state) when is_list(segments) and is_map(state) do
    build_snapshots(segments, state, :progress, [])
  end

  def final_snapshots(segments, state, manual_scores \\ [])
      when is_list(segments) and is_map(state) and is_list(manual_scores) do
    auto_scores =
      build_snapshots(segments, state, :final, manual_scores)
      |> Map.new(fn score -> {score[:section_id] || score["section_id"], score} end)

    manual_scores
    |> normalize_manual_scores()
    |> Enum.reduce(auto_scores, fn score, acc ->
      Map.put(acc, score.section_id, Map.put(score, :kind, "final"))
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.section_id)
  end

  defp build_snapshots(segments, state, kind, manual_scores) do
    manual_sections =
      manual_scores
      |> normalize_manual_scores()
      |> MapSet.new(& &1.section_id)

    segments
    |> Enum.group_by(&segment_section_id/1)
    |> Enum.sort_by(fn {section_id, _segments} -> section_id end)
    |> Enum.flat_map(fn {_section_id, section_segments} ->
      if scoreable_section?(section_segments) do
        case snapshot_for_section(section_segments, state, kind, manual_sections) do
          nil -> []
          snapshot -> [snapshot]
        end
      else
        []
      end
    end)
  end

  defp snapshot_for_section(section_segments, state, :progress, _manual_sections) do
    format = section_format(section_segments)
    section_id = hd(section_segments) |> segment_section_id()

    base =
      case format do
        "for_time" ->
          reps_progress_snapshot(section_segments, state)

        "kcal_target" ->
          time_progress_snapshot(section_id, state)

        "amrap" ->
          rounds_reps_progress_snapshot(section_segments, state)

        "edt" ->
          reps_progress_snapshot(section_segments, state)

        "death_by" ->
          dynamic_reps_progress_snapshot(section_segments, state, &death_by_round_reps/2)

        "ladder_ascending" ->
          dynamic_reps_progress_snapshot(section_segments, state, &ascending_round_reps/2)

        "ladder_descending" ->
          dynamic_reps_progress_snapshot(section_segments, state, &descending_round_reps/2)

        "pyramid" ->
          dynamic_reps_progress_snapshot(section_segments, state, &pyramid_round_reps/2)

        "train_to_exhaustion" ->
          reps_progress_snapshot(section_segments, state)

        "hrr" ->
          rounds_progress_snapshot(section_segments, state, "cycles")

        "emom" ->
          emom_progress_snapshot(section_segments, state)

        "complex_emom" ->
          emom_progress_snapshot(section_segments, state)

        _other ->
          generic_progress_snapshot(section_segments, state)
      end

    snapshot(section_id, base, "progress", "auto")
  end

  defp snapshot_for_section(section_segments, state, :final, manual_sections) do
    section_id = hd(section_segments) |> segment_section_id()

    if MapSet.member?(manual_sections, section_id) do
      nil
    else
      format = section_format(section_segments)

      base =
        if format in ["emom", "complex_emom"] do
          emom_final_snapshot(section_segments, state)
        else
          score_type = final_score_type(format, score_config(section_segments))

          result =
            case score_type do
              "time" -> time_final_snapshot(section_id, state)
              "rounds+reps" -> rounds_reps_progress_snapshot(section_segments, state)
              "reps" -> reps_final_snapshot(section_segments, state, format)
              "rounds" -> rounds_progress_snapshot(section_segments, state, "rounds")
              _other -> generic_progress_snapshot(section_segments, state)
            end

          result && Map.put(result, :score_type, score_type)
        end

      snapshot(section_id, base, "final", "auto")
    end
  end

  defp snapshot(_section_id, nil, _kind, _source), do: nil

  defp snapshot(_section_id, %{value: nil}, _kind, _source), do: nil

  defp snapshot(section_id, base, kind, source) do
    %{
      section_id: section_id,
      value: base.value,
      unit: base[:unit],
      score_type: base[:score_type],
      source: source,
      kind: kind
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp time_progress_snapshot(section_id, state) do
    case section_elapsed_ms(state, section_id) do
      elapsed when elapsed > 0 -> %{value: format_duration(elapsed), score_type: "time"}
      _other -> nil
    end
  end

  defp time_final_snapshot(section_id, state), do: time_progress_snapshot(section_id, state)

  defp reps_final_snapshot(section_segments, state, format) do
    case format do
      "death_by" ->
        dynamic_reps_progress_snapshot(section_segments, state, &death_by_round_reps/2)

      "ladder_ascending" ->
        dynamic_reps_progress_snapshot(section_segments, state, &ascending_round_reps/2)

      "ladder_descending" ->
        dynamic_reps_progress_snapshot(section_segments, state, &descending_round_reps/2)

      "pyramid" ->
        dynamic_reps_progress_snapshot(section_segments, state, &pyramid_round_reps/2)

      _other ->
        reps_progress_snapshot(section_segments, state)
    end
  end

  defp reps_progress_snapshot(section_segments, state) do
    total =
      Enum.reduce(section_segments, 0, fn segment, acc ->
        acc + completed_cycles(segment, state) * cycle_reps(segment) +
          partial_checked_reps(segment, state)
      end)

    if total > 0, do: %{value: total, unit: "reps", score_type: "reps"}, else: nil
  end

  defp rounds_reps_progress_snapshot(section_segments, state) do
    rounds = section_segments |> Enum.map(&completed_cycles(&1, state)) |> Enum.sum()

    partial_reps =
      case Enum.find(section_segments, &(partial_checked_steps(&1, state) > 0)) do
        nil -> 0
        segment -> partial_checked_reps(segment, state)
      end

    if rounds > 0 or partial_reps > 0 do
      %{value: format_rounds_reps(rounds, partial_reps), score_type: "rounds+reps"}
    else
      nil
    end
  end

  defp rounds_progress_snapshot(section_segments, state, unit) do
    rounds =
      section_segments
      |> Enum.map(&completed_cycles(&1, state))
      |> Enum.sum()

    if rounds > 0, do: %{value: rounds, unit: unit, score_type: "rounds"}, else: nil
  end

  defp dynamic_reps_progress_snapshot(section_segments, state, round_reps_fun) do
    segment = hd(section_segments)
    step_count = segment_step_count(segment)
    cycles = completed_cycles(segment, state)
    timer_config = segment[:timer_config] || segment["timer_config"] || %{}

    completed_reps =
      if cycles > 0 do
        Enum.reduce(1..cycles, 0, fn round_number, acc ->
          acc + step_count * round_reps_fun.(timer_config, round_number)
        end)
      else
        0
      end

    partial_reps =
      partial_checked_steps(segment, state) * round_reps_fun.(timer_config, cycles + 1)

    total = completed_reps + partial_reps

    if total > 0, do: %{value: total, unit: "reps", score_type: "reps"}, else: nil
  end

  # ── EMOM: scoring-mode-aware snapshots ───────────────────────────────────────

  defp emom_scoring_mode(section_segments) do
    tc = hd(section_segments) |> Map.get(:timer_config) || %{}
    tc[:scoring_mode] || tc["scoring_mode"] || "amrap"
  end

  defp emom_amrap_scoring_style(section_segments) do
    tc = hd(section_segments) |> Map.get(:timer_config) || %{}
    tc[:amrap_scoring_style] || tc["amrap_scoring_style"] || "grand_total"
  end

  defp emom_progress_snapshot(section_segments, state) do
    section_id = hd(section_segments) |> segment_section_id()

    case emom_scoring_mode(section_segments) do
      "for_time" ->
        elapsed = section_elapsed_ms(state, section_id)

        if elapsed > 0,
          do: %{value: format_duration(elapsed), score_type: "accumulated_work_time"},
          else: nil

      "for_quality" ->
        survived = Enum.count(section_segments, &(completed_cycles(&1, state) > 0))

        if survived > 0,
          do: %{value: survived, unit: "intervals", score_type: "intervals_survived"},
          else: nil

      "amrap" ->
        emom_reps_snapshot(section_segments, state)

      "to_failure" ->
        survived = Enum.count(section_segments, &(completed_cycles(&1, state) > 0))

        if survived > 0,
          do: %{value: survived, unit: "intervals", score_type: "intervals_survived"},
          else: nil

      _ ->
        emom_reps_snapshot(section_segments, state)
    end
  end

  defp emom_final_snapshot(section_segments, state) do
    section_id = hd(section_segments) |> segment_section_id()
    format = section_format(section_segments)

    case emom_scoring_mode(section_segments) do
      "for_time" ->
        elapsed = section_elapsed_ms(state, section_id)

        if elapsed > 0,
          do: %{value: format_duration(elapsed), score_type: "accumulated_work_time"},
          else: nil

      "for_quality" ->
        total = length(section_segments)
        survived = Enum.count(section_segments, &(completed_cycles(&1, state) > 0))
        result = if survived >= total, do: "Pass", else: "Fail"
        %{value: result, score_type: "pass_fail"}

      "amrap" when format == "complex_emom" ->
        case emom_amrap_scoring_style(section_segments) do
          "lowest_window" ->
            window_reps =
              Enum.map(section_segments, fn seg ->
                completed_cycles(seg, state) * cycle_reps(seg)
              end)

            case Enum.filter(window_reps, &(&1 > 0)) do
              [] -> nil
              nonzero -> %{value: Enum.min(nonzero), unit: "reps", score_type: "reps"}
            end

          _ ->
            emom_reps_snapshot(section_segments, state)
        end

      "amrap" ->
        emom_reps_snapshot(section_segments, state)

      "to_failure" ->
        survived = Enum.count(section_segments, &(completed_cycles(&1, state) > 0))

        if survived > 0,
          do: %{value: survived, unit: "intervals", score_type: "intervals_survived"},
          else: nil

      _ ->
        emom_reps_snapshot(section_segments, state)
    end
  end

  defp emom_reps_snapshot(section_segments, state) do
    total_reps =
      Enum.reduce(section_segments, 0, fn seg, acc ->
        acc + completed_cycles(seg, state) * cycle_reps(seg)
      end)

    if total_reps > 0, do: %{value: total_reps, unit: "reps", score_type: "reps"}, else: nil
  end

  defp generic_progress_snapshot(section_segments, state) do
    cond do
      section_format(section_segments) in @time_fallback_formats ->
        time_progress_snapshot(hd(section_segments) |> segment_section_id(), state)

      true ->
        reps_progress_snapshot(section_segments, state)
    end
  end

  defp normalize_manual_scores(scores) do
    Enum.flat_map(scores, fn score ->
      section_id = score[:section_id] || score["section_id"]
      value = score[:value] || score["value"]
      unit = score[:unit] || score["unit"]
      score_type = score[:score_type] || score["score_type"]

      if blank?(section_id) or blank?(value) do
        []
      else
        [
          %{
            section_id: section_id,
            value: value,
            unit: blank_to_nil(unit),
            score_type: blank_to_nil(score_type),
            source: "manual"
          }
        ]
      end
    end)
  end

  defp final_score_type(format, score_config) do
    cond do
      format in ~w(for_time kcal_target ladder_descending pyramid hrr) -> "time"
      format == "amrap" -> "rounds+reps"
      format in ~w(edt death_by ladder_ascending train_to_exhaustion) -> "reps"
      true -> score_config[:type] || score_config["type"]
    end
  end

  defp scoreable_section?(segments), do: Enum.any?(segments, &segment_scoreable?/1)

  defp segment_scoreable?(segment), do: segment[:scoreable] || segment["scoreable"] || false

  defp section_format([segment | _rest]), do: segment[:format] || segment["format"] || "untimed"

  defp score_config([segment | _rest]),
    do: segment[:score_config] || segment["score_config"] || %{}

  defp segment_section_id(segment), do: segment[:section_id] || segment["section_id"]

  defp segment_key(segment), do: segment[:segment_key] || segment["segment_key"]

  defp completed_cycles(segment, state) do
    state
    |> Map.get(:segment_cycle_counts, Map.get(state, "segment_cycle_counts", %{}))
    |> read_int(segment_key(segment))
  end

  defp section_elapsed_ms(state, section_id) do
    state
    |> Map.get(:section_elapsed_ms, Map.get(state, "section_elapsed_ms", %{}))
    |> read_int(section_id)
  end

  defp partial_checked_steps(segment, state) do
    checked_ids =
      Map.get(state, :checked_exercise_ids, Map.get(state, "checked_exercise_ids", []))

    step_ids = segment_step_ids(segment)
    Enum.count(step_ids, &(&1 in checked_ids))
  end

  defp partial_checked_reps(segment, state) do
    segment_step_definitions(segment)
    |> Enum.filter(fn %{step_id: step_id} ->
      step_id in Map.get(state, :checked_exercise_ids, Map.get(state, "checked_exercise_ids", []))
    end)
    |> Enum.reduce(0, fn step, acc -> acc + step.reps end)
  end

  defp cycle_reps(segment) do
    segment_step_definitions(segment)
    |> Enum.reduce(0, fn step, acc -> acc + step.reps end)
  end

  defp segment_step_ids(segment) do
    Enum.map(segment_step_definitions(segment), & &1.step_id)
  end

  defp segment_step_count(segment), do: length(segment_step_definitions(segment))

  defp segment_step_definitions(segment) do
    segment
    |> segment_exercises()
    |> Enum.filter(&(not truthy?(&1[:excluded] || &1["excluded"])))
    |> Enum.flat_map(fn exercise ->
      set_count =
        exercise[:sets] || exercise["sets"] || 1

      reps =
        exercise[:prescription_value] || exercise["prescription_value"] || 1

      Enum.map(1..set_count, fn set_number ->
        %{
          step_id: build_step_id(segment, exercise, set_count, set_number),
          reps: reps
        }
      end)
    end)
  end

  defp build_step_id(segment, exercise, 1, _set_number),
    do: "#{segment_key(segment)}::#{exercise[:id] || exercise["id"]}"

  defp build_step_id(segment, exercise, _set_count, set_number),
    do: "#{segment_key(segment)}::#{exercise[:id] || exercise["id"]}::set:#{set_number}"

  defp segment_exercises(segment), do: segment[:exercises] || segment["exercises"] || []

  defp death_by_round_reps(timer_config, round_number) do
    start_reps = timer_config[:start_reps] || timer_config["start_reps"] || 1
    step_reps = timer_config[:step_reps] || timer_config["step_reps"] || 1
    start_reps + step_reps * (round_number - 1)
  end

  defp ascending_round_reps(timer_config, round_number),
    do: death_by_round_reps(timer_config, round_number)

  defp descending_round_reps(timer_config, round_number) do
    start_reps = timer_config[:start_reps] || timer_config["start_reps"] || 1
    step_reps = timer_config[:step_reps] || timer_config["step_reps"] || 1
    min_reps = timer_config[:min_reps] || timer_config["min_reps"] || 1

    max(start_reps - step_reps * (round_number - 1), min_reps)
  end

  defp pyramid_round_reps(timer_config, round_number) do
    peak_reps = timer_config[:peak_reps] || timer_config["peak_reps"] || 1
    step_reps = timer_config[:step_reps] || timer_config["step_reps"] || 1

    ascending =
      step_reps..peak_reps
      |> Enum.to_list()
      |> Enum.take_every(step_reps)

    descending = ascending |> Enum.reverse() |> tl()
    rounds = ascending ++ descending

    Enum.at(rounds, round_number - 1, List.last(rounds) || peak_reps)
  end

  defp format_rounds_reps(rounds, 0), do: "#{rounds} rounds"
  defp format_rounds_reps(0, reps), do: "#{reps} reps"
  defp format_rounds_reps(rounds, reps), do: "#{rounds} rounds + #{reps} reps"

  defp format_duration(elapsed_ms) when is_integer(elapsed_ms) do
    total_seconds = Integer.floor_div(elapsed_ms, 1000)
    minutes = Integer.floor_div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  defp read_int(map, key) do
    case Map.get(map, key) || Map.get(map, to_string(key)) do
      value when is_integer(value) and value >= 0 -> value
      _other -> 0
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
