defmodule MilosTraining.Execution.Domain.TimerSequenceBuilder do
  @moduledoc """
  Pure domain module that converts a materialized workout into a flat ordered
  sequence of executable timer segments. Each segment describes one discrete
  timed (or manual) phase the athlete works through during execution.

  Supports all 18 timer formats. Section traversal is depth-first (nested
  sections are expanded inline) to match the workout authoring display order.
  """

  @doc """
  Builds a flat list of timer segments from a workout map. Each segment is a map with:
    - :section_id        — originating section id
    - :section_name      — display name
    - :format            — timer format atom
    - :kind              — :countdown | :countup | :manual | :no_timer | :interval_cycle
    - :duration_seconds  — nil for manual/no_timer
    - :round             — round index within the section (1-based), nil for non-cycling formats
    - :total_rounds      — total rounds for cycling formats, nil otherwise
    - :label             — human-readable display string for the timer phase
    - :exercises         — list of exercise maps relevant to this segment
    - :score_config      — score config map from the section (nil if not scoreable)
    - :scoreable         — boolean
  """
  def build(workout) do
    sections = workout[:sections] || workout["sections"] || []

    top_level =
      sections
      |> Enum.filter(&is_nil(&1[:parent_section_id] || &1["parent_section_id"]))
      |> sort_sections()

    top_level
    |> Enum.flat_map(fn section ->
      build_section(section, sections)
    end)
    |> Enum.with_index()
    |> Enum.map(fn {segment, index} ->
      Map.put(segment, :segment_key, "segment:#{index}")
    end)
  end

  defp build_section(section, all_sections) do
    child_sections = children_of(section, all_sections)
    own_segments = build_own_segments(section, child_sections)
    nested_segments = Enum.flat_map(child_sections, &build_section(&1, all_sections))

    own_segments ++ nested_segments
  end

  defp build_own_segments(section, child_sections) do
    format = section_format(section)
    exercises = section_exercises(section)

    case format do
      "untimed" ->
        if child_sections == [] or exercises != [] do
          [segment(section, :no_timer, nil, nil, nil, exercises)]
        else
          []
        end

      "for_time" ->
        cap = get_timer_field(section, :time_cap_seconds)
        [segment(section, :countup, cap, nil, nil, exercises)]

      "train_to_exhaustion" ->
        [segment(section, :manual, nil, nil, nil, exercises)]

      "kcal_target" ->
        target = get_timer_field(section, :kcal_target)
        cap = get_timer_field(section, :time_cap_seconds)
        label = if target, do: "#{target} kcal", else: "Kcal target"
        [segment(section, :countup, cap, nil, nil, exercises, label: label)]

      "amrap" ->
        duration = get_timer_field(section, :duration_seconds)
        [segment(section, :countdown, duration, nil, nil, exercises)]

      "edt" ->
        duration = get_timer_field(section, :duration_seconds)
        [segment(section, :countdown, duration, nil, nil, exercises)]

      "death_by" ->
        # No fixed duration — athlete goes until failure; manual progression
        [segment(section, :manual, nil, nil, nil, exercises)]

      "emom" ->
        build_emom_segments(section, exercises)

      "complex_emom" ->
        build_emom_segments(section, exercises)

      "even_odd" ->
        build_even_odd_segments(section, exercises)

      "billat" ->
        build_billat_segments(section, exercises)

      "tabata" ->
        build_tabata_segments(section, exercises)

      "custom_hiit" ->
        build_tabata_segments(section, exercises)

      "cluster" ->
        build_cluster_segments(section, exercises)

      "hrr" ->
        build_hrr_segments(section, exercises)

      "ladder_ascending" ->
        [segment(section, :manual, nil, nil, nil, exercises)]

      "ladder_descending" ->
        [segment(section, :manual, nil, nil, nil, exercises)]

      "pyramid" ->
        [segment(section, :manual, nil, nil, nil, exercises)]

      "rest" ->
        duration = get_timer_field(section, :duration_seconds)
        [segment(section, :countdown, duration, nil, nil, [], label: "Rest")]

      _ ->
        [segment(section, :no_timer, nil, nil, nil, exercises)]
    end
  end

  # ── EMOM: one segment per minute, cycling exercises per round ─────────────────

  defp build_emom_segments(section, exercises) do
    duration = get_timer_field(section, :duration_seconds) || 0
    interval = get_timer_field(section, :interval_seconds) || 60
    scoring_mode = get_timer_field(section, :scoring_mode) || "amrap"
    max_windows = get_timer_field(section, :max_windows) || 100

    {total_rounds, effective_duration} =
      cond do
        scoring_mode == "to_failure" ->
          {max_windows, 0}

        interval > 0 and duration > 0 ->
          {max(ceil(duration / interval), 1), duration}

        true ->
          {1, duration}
      end

    if total_rounds > 0 do
      Enum.map(1..total_rounds, fn round ->
        round_exercises =
          if exercises == [] do
            []
          else
            round_exercises_for_emom(exercises, round, total_rounds)
          end

        segment(
          section,
          :countdown,
          interval_duration(effective_duration, interval, round),
          round,
          total_rounds,
          round_exercises,
          label: "Min #{round}"
        )
      end)
    else
      []
    end
  end

  defp round_exercises_for_emom(exercises, round, total_rounds) do
    # For complex_emom / even_odd the exercises have interval_assignment.
    # For plain emom, all exercises repeat every round.
    has_assignment =
      Enum.any?(exercises, &((&1[:interval_assignment] || &1["interval_assignment"]) != nil))

    if has_assignment do
      Enum.filter(exercises, fn ex ->
        assignment = ex[:interval_assignment] || ex["interval_assignment"]
        # cycle assignment through rounds when assignment > total_rounds
        if assignment, do: rem(round - 1, total_rounds) + 1 == assignment, else: true
      end)
    else
      exercises
    end
  end

  # ── Even/Odd: two groups alternating per interval ────────────────────────────

  defp build_even_odd_segments(section, exercises) do
    duration = get_timer_field(section, :duration_seconds) || 0
    interval = get_timer_field(section, :interval_seconds) || 60

    total_rounds =
      if interval > 0 do
        max(ceil(duration / interval), 1)
      else
        1
      end

    Enum.map(1..total_rounds, fn round ->
      parity = if rem(round, 2) == 1, do: 1, else: 2

      round_exercises =
        Enum.filter(exercises, fn ex ->
          assignment = ex[:interval_assignment] || ex["interval_assignment"]
          is_nil(assignment) or assignment == parity
        end)

      label = if rem(round, 2) == 1, do: "Odd – Min #{round}", else: "Even – Min #{round}"

      segment(
        section,
        :countdown,
        interval_duration(duration, interval, round),
        round,
        total_rounds,
        round_exercises,
        label: label
      )
    end)
  end

  # ── Billat: work/rest cycles ─────────────────────────────────────────────────

  defp build_billat_segments(section, exercises) do
    work = get_timer_field(section, :work_seconds) || 0
    rest = get_timer_field(section, :rest_seconds) || 0
    cycles = get_timer_field(section, :cycles) || 1

    Enum.flat_map(1..cycles, fn round ->
      [
        segment(section, :countdown, work, round, cycles, exercises,
          label: "Work #{round}/#{cycles}"
        ),
        segment(section, :countdown, rest, round, cycles, [], label: "Rest #{round}/#{cycles}")
      ]
    end)
  end

  # ── Tabata / Custom HIIT ─────────────────────────────────────────────────────

  defp build_tabata_segments(section, exercises) do
    work = get_timer_field(section, :work_seconds) || 20
    rest = get_timer_field(section, :rest_seconds) || 10
    rounds = get_timer_field(section, :rounds) || 8

    Enum.flat_map(1..rounds, fn round ->
      [
        segment(section, :countdown, work, round, rounds, exercises,
          label: "Work #{round}/#{rounds}"
        ),
        segment(section, :countdown, rest, round, rounds, [], label: "Rest #{round}/#{rounds}")
      ]
    end)
  end

  # ── Cluster: intra-set rest between sets ─────────────────────────────────────

  defp build_cluster_segments(section, exercises) do
    sets = get_timer_field(section, :sets) || 1
    intra_rest = get_timer_field(section, :intra_rest_seconds) || 0

    Enum.flat_map(1..sets, fn set_num ->
      work_seg =
        segment(section, :manual, nil, set_num, sets, exercises, label: "Set #{set_num}/#{sets}")

      if set_num < sets and intra_rest > 0 do
        rest_seg =
          segment(section, :countdown, intra_rest, set_num, sets, [], label: "Intra Rest")

        [work_seg, rest_seg]
      else
        [work_seg]
      end
    end)
  end

  # ── HRR: effort then HR recovery period ──────────────────────────────────────

  defp build_hrr_segments(section, exercises) do
    effort = get_timer_field(section, :effort_seconds) || 0
    hr_zone = get_timer_field(section, :hr_zone)
    zone_label = if hr_zone, do: " (Zone #{hr_zone})", else: ""

    [
      segment(section, :countdown, effort, nil, nil, exercises, label: "Effort#{zone_label}"),
      segment(section, :manual, nil, nil, nil, [], label: "Recover to HR")
    ]
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp segment(section, kind, duration, round, total_rounds, exercises, opts \\ []) do
    id = section[:id] || section["id"]
    name = section[:name] || section["name"] || ""
    format = section_format(section)
    scoreable = section[:scoreable] || section["scoreable"] || false
    score_config = section[:score_config] || section["score_config"]
    label = Keyword.get(opts, :label, name)

    %{
      segment_key: nil,
      section_id: id,
      section_name: name,
      format: format,
      kind: kind,
      duration_seconds: duration,
      round: round,
      total_rounds: total_rounds,
      label: label,
      exercises: exercises,
      scoreable: scoreable,
      score_config: score_config,
      timer_config: section[:timer_config] || section["timer_config"] || %{}
    }
  end

  defp section_format(section) do
    config = section[:timer_config] || section["timer_config"] || %{}
    config[:type] || config["type"] || "untimed"
  end

  defp section_exercises(section) do
    section[:exercises] || section["exercises"] || []
  end

  defp children_of(section, all_sections) do
    parent_id = section[:id] || section["id"]

    all_sections
    |> Enum.filter(fn s ->
      pid = s[:parent_section_id] || s["parent_section_id"]
      pid == parent_id
    end)
    |> sort_sections()
  end

  defp get_timer_field(section, key) do
    config = section[:timer_config] || section["timer_config"] || %{}
    config[key] || config[Atom.to_string(key)]
  end

  defp interval_duration(duration, interval, round) do
    if duration > 0 and interval > 0 do
      remaining = duration - interval * (round - 1)
      max(min(interval, remaining), 1)
    else
      interval
    end
  end

  defp sort_sections(sections) do
    Enum.sort_by(sections, &(&1[:order] || &1["order"] || 0))
  end
end
