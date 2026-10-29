defmodule Palee.Execution.Domain.TimerSequenceBuilder do
  @moduledoc """
  Pure domain module that converts a materialized workout into a flat ordered
  sequence of executable timer segments. Each segment describes one discrete
  timed (or manual) phase the athlete works through during execution.

  Supports all 19 timer formats. Section traversal is depth-first (nested
  sections are expanded inline) to match the workout authoring display order.
  """

  @doc """
  Builds a flat list of timer segments from a workout map. Each segment is a map with:
    - :section_id        — originating section id (between-section segments use
                           a synthetic `<id>:transition` / `<id>:rest-after` id)
    - :section_name      — display name
    - :format            — timer format atom
    - :kind              — :countdown | :countup | :manual | :no_timer | :interval_cycle
    - :phase             — "work" | "rest" | "transition"
    - :duration_seconds  — countdown length, count-up cap, or the window length of
                           an :interval_cycle; nil when untimed
    - :round             — round index within the section (1-based), nil for non-cycling formats
    - :total_rounds      — total rounds (or the window cap of an :interval_cycle), nil otherwise
    - :label             — English display string for the timer phase
    - :label_key         — stable key for localizing the label (nil: use the section name)
    - :label_params      — values interpolated into the localized label
    - :exercises         — list of exercise maps relevant to this segment
    - :score_config      — score config map from the section (nil if not scoreable)
    - :scoreable         — boolean

  An `:interval_cycle` segment repeats its window (`duration_seconds`, or the
  section's `interval_pattern_seconds`) until the athlete stops or `total_rounds`
  windows have elapsed — used for open-ended formats such as Death By and
  EMOM-to-failure instead of materializing hundreds of one-minute segments.
  """
  def build(workout) do
    sections =
      workout
      |> value(:sections, [])
      |> flatten_nested_sections()

    top_level =
      sections
      |> Enum.filter(&is_nil(&1[:parent_section_id] || &1["parent_section_id"]))
      |> sort_sections()

    top_level
    |> Enum.flat_map(fn section ->
      build_section(section, sections)
    end)
    |> trim_between_section_segments()
    |> Enum.with_index()
    |> Enum.map(fn {segment, index} ->
      Map.put(segment, :segment_key, "segment:#{index}")
    end)
  end

  @doc """
  Summarizes the sequence an athlete will run for authoring previews: one slim
  entry per segment plus the total length of the timed part. `open_ended` is
  true when any segment only ends when the athlete says so (stopwatches,
  manual steps, uncapped interval cycles).
  """
  def preview(workout) do
    segments = build(workout)

    %{
      segments:
        Enum.map(
          segments,
          &Map.take(&1, [
            :label,
            :label_key,
            :label_params,
            :kind,
            :phase,
            :duration_seconds,
            :round,
            :total_rounds
          ])
        ),
      total_seconds: Enum.reduce(segments, 0, &(&2 + timed_seconds(&1))),
      open_ended: Enum.any?(segments, &open_ended?/1)
    }
  end

  defp timed_seconds(%{kind: :countdown, duration_seconds: seconds}), do: seconds

  defp timed_seconds(%{kind: :interval_cycle, duration_seconds: seconds, total_rounds: rounds})
       when is_integer(rounds),
       do: seconds * rounds

  defp timed_seconds(_segment), do: 0

  defp open_ended?(%{kind: :countdown}), do: false
  defp open_ended?(%{kind: :interval_cycle, total_rounds: rounds}), do: not is_integer(rounds)
  defp open_ended?(_segment), do: true

  defp build_section(section, all_sections) do
    child_sections = children_of(section, all_sections)

    own_segments =
      section
      |> build_own_segments(child_sections)
      |> Enum.reject(&empty_countdown?/1)

    nested_segments = Enum.flat_map(child_sections, &build_section(&1, all_sections))

    case own_segments ++ nested_segments do
      [] -> []
      body -> transition_segments(section) ++ body ++ rest_after_segments(section)
    end
  end

  # A transition before the first section, or a rest after the last one, has
  # nothing to separate.
  defp trim_between_section_segments(segments) do
    segments
    |> Enum.drop_while(&between_sections?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&between_sections?/1)
    |> Enum.reverse()
  end

  defp between_sections?(segment), do: Map.get(segment, :between_sections, false)

  defp empty_countdown?(%{kind: :countdown, duration_seconds: duration}),
    do: not (is_integer(duration) and duration > 0)

  defp empty_countdown?(_segment), do: false

  defp transition_segments(section) do
    case positive(
           get_timer_field(section, :transition_seconds) ||
             metadata(section, "transition_seconds")
         ) do
      nil ->
        []

      seconds ->
        [between_segment(section, "transition", seconds, "transition", text("transition"))]
    end
  end

  defp rest_after_segments(section) do
    case positive(
           section[:rest_before_next_section_seconds] ||
             section["rest_before_next_section_seconds"]
         ) do
      nil -> []
      seconds -> [between_segment(section, "rest-after", seconds, "rest", text("rest"))]
    end
  end

  defp between_segment(section, suffix, seconds, phase, label) do
    id = section[:id] || section["id"]

    section
    |> segment(:countdown, seconds, nil, nil, [], [phase: phase] ++ label)
    |> Map.merge(%{
      section_id: "#{id}:#{suffix}",
      scoreable: false,
      score_config: nil,
      between_sections: true
    })
  end

  defp build_own_segments(section, child_sections) do
    case plan_clock(section) do
      %{} = clock -> build_plan_segments(section, clock)
      nil -> build_format_segments(section, child_sections)
    end
  end

  defp build_format_segments(section, child_sections) do
    format = section_format(section)
    exercises = section_exercises(section)

    case format do
      "untimed" ->
        if child_sections == [] or exercises != [] do
          build_untimed_segments(section, exercises)
        else
          []
        end

      "for_time" ->
        cap = get_timer_field(section, :time_cap_seconds)
        rounds = positive(get_timer_field(section, :rounds))
        total_rounds = if rounds && rounds > 1, do: rounds

        [segment(section, :countup, cap, nil, total_rounds, exercises)]

      "train_to_exhaustion" ->
        build_train_to_exhaustion_segments(section, exercises)

      "kcal_target" ->
        target = get_timer_field(section, :kcal_target)
        cap = get_timer_field(section, :time_cap_seconds)

        label =
          if target, do: text("kcal_target", %{kcal: target}), else: text("kcal_target_open")

        [segment(section, :countup, cap, nil, nil, exercises, label)]

      "amrap" ->
        duration = get_timer_field(section, :duration_seconds)
        [segment(section, :countdown, duration, nil, nil, exercises)]

      "edt" ->
        duration = get_timer_field(section, :duration_seconds)
        [segment(section, :countdown, duration, nil, nil, exercises)]

      "death_by" ->
        # An EMOM by definition: one window per interval, reps grow each window,
        # and it ends when the athlete fails (or at the optional round cap).
        interval = positive(get_timer_field(section, :interval_seconds)) || 60
        cap = positive(get_timer_field(section, :ladder_cap))
        [segment(section, :interval_cycle, interval, nil, cap, exercises, text("death_by"))]

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

      ladder when ladder in ["ladder_ascending", "ladder_descending", "pyramid"] ->
        cap = positive(get_timer_field(section, :time_cap_seconds))
        [segment(section, :countup, cap, nil, nil, exercises)]

      "rest" ->
        duration = get_timer_field(section, :duration_seconds)

        kind = if is_integer(duration) and duration > 0, do: :countdown, else: :manual
        [segment(section, kind, duration, nil, nil, [], [phase: "rest"] ++ text("rest"))]

      _ ->
        [segment(section, :no_timer, nil, nil, nil, exercises)]
    end
  end

  # ── Structured plan (ADR-270): the clock of the plan's read model ───────────
  #
  # A section written in the structured WOD editor runs as its plan's flow
  # says (`sections[].prescription.clock`, unit-normalised by the Workouts
  # context). Its segments carry the format `structured_plan`, so the score
  # is the one its plan sets (`score_config`), as the plan runner sends it.

  @max_plan_segments 200

  defp plan_clock(section) do
    case section[:prescription] || section["prescription"] do
      %{} = prescription ->
        case prescription[:clock] || prescription["clock"] do
          %{} = clock -> clock
          _none -> nil
        end

      _none ->
        nil
    end
  end

  defp build_plan_segments(section, clock) do
    section = Map.put(section, :timer_config, %{"type" => "structured_plan"})
    exercises = section_exercises(section)
    get = fn key -> clock[key] || clock[Atom.to_string(key)] end

    plan_segments(get.(:flow), section, exercises, get)
  end

  defp plan_segments("sets", section, exercises, get) do
    rounds = min(positive(get.(:total_rounds)) || 1, @max_plan_segments)
    rest = get.(:rest_secs) |> range_min() |> positive()

    if rounds > 1 do
      with_rests(1..rounds, rest, fn set_num ->
        segment(
          section,
          :no_timer,
          nil,
          set_num,
          rounds,
          exercises,
          text("set", %{set: set_num, total: rounds})
        )
      end)
    else
      [segment(section, :no_timer, nil, nil, nil, exercises)]
    end
  end

  defp plan_segments("for_time", section, exercises, get) do
    rounds = positive(get.(:rounds))
    total_rounds = if rounds && rounds > 1, do: rounds
    [segment(section, :countup, positive(get.(:cap_secs)), nil, total_rounds, exercises)]
  end

  defp plan_segments("amrap", section, exercises, get) do
    case Enum.filter(List.wrap(get.(:windows_secs)), &positive/1) do
      [] ->
        [segment(section, :countup, nil, nil, nil, exercises)]

      [window] ->
        [segment(section, :countdown, window, nil, nil, exercises)]

      windows ->
        total = length(windows)
        rest = get.(:rest_secs) |> range_min() |> positive()

        with_rests(1..total, rest, fn round ->
          segment(
            section,
            :countdown,
            Enum.at(windows, round - 1),
            round,
            total,
            exercises,
            text("round", %{round: round, total: total})
          )
        end)
    end
  end

  defp plan_segments("emom", section, exercises, get) do
    every = positive(get.(:every_secs)) || 60
    [segment(section, :interval_cycle, every, nil, positive(get.(:times)), exercises, text("emom"))]
  end

  defp plan_segments("intervals", section, exercises, get) do
    rounds = min(positive(get.(:rounds)) || 1, @max_plan_segments)
    work = positive(get.(:work_secs))
    off = positive(get.(:off_secs))
    hr = positive(get.(:hr_target_bpm))

    Enum.flat_map(1..rounds, fn round ->
      work_segment =
        segment(
          section,
          if(work, do: :countdown, else: :countup),
          work,
          round,
          rounds,
          exercises,
          text("work", %{round: round, total: rounds})
        )

      cond do
        round == rounds -> [work_segment]
        off -> [work_segment, rest_after(work_segment, off)]
        hr -> [work_segment, %{rest_after(work_segment, nil) | kind: :manual} |> recover_label()]
        true -> [work_segment]
      end
    end)
  end

  defp plan_segments("rest", section, _exercises, get) do
    duration = positive(get.(:dur_secs))
    kind = if duration, do: :countdown, else: :manual
    [segment(section, kind, duration, nil, nil, [], [phase: "rest"] ++ text("rest"))]
  end

  defp plan_segments(_flow, section, exercises, _get),
    do: [segment(section, :no_timer, nil, nil, nil, exercises)]

  defp recover_label(segment) do
    [label: label, label_key: key, label_params: params] = text("recover")
    %{segment | label: label, label_key: key, label_params: params}
  end

  defp range_min(%{} = range), do: range[:min] || range["min"]
  defp range_min(_range), do: nil

  # ── Untimed: optional authored rounds with rest between them ─────────────────

  defp build_untimed_segments(section, exercises) do
    rounds = positive(metadata(section, "rounds")) || 1
    rest = positive(metadata(section, "rest_between_rounds_seconds"))

    if rounds > 1 do
      with_rests(1..rounds, rest, fn round ->
        segment(
          section,
          :no_timer,
          nil,
          round,
          rounds,
          exercises,
          text("round", %{round: round, total: rounds})
        )
      end)
    else
      [segment(section, :no_timer, nil, nil, nil, exercises)]
    end
  end

  # ── Train to exhaustion: sets to failure with optional rest between ──────────

  defp build_train_to_exhaustion_segments(section, exercises) do
    sets = positive(get_timer_field(section, :rounds)) || 1
    rest = positive(get_timer_field(section, :rest_seconds))
    cap = positive(get_timer_field(section, :time_cap_seconds))

    if sets > 1 do
      with_rests(1..sets, rest, fn set_num ->
        segment(
          section,
          :countup,
          cap,
          set_num,
          sets,
          exercises,
          text("set", %{set: set_num, total: sets})
        )
      end)
    else
      [segment(section, :countup, cap, nil, nil, exercises)]
    end
  end

  # ── EMOM: one segment per window, cycling exercises per round ────────────────

  defp build_emom_segments(section, exercises) do
    duration = get_timer_field(section, :duration_seconds) || 0
    interval = get_timer_field(section, :interval_seconds) || 60
    pattern = interval_pattern(section)
    scoring_mode = get_timer_field(section, :scoring_mode) || "amrap"

    if scoring_mode == "to_failure" do
      cap = positive(get_timer_field(section, :max_windows))
      window = if pattern, do: hd(pattern), else: interval

      [segment(section, :interval_cycle, window, nil, cap, exercises, text("emom"))]
    else
      windows = emom_windows(duration, pattern || [interval])
      total_rounds = length(windows)
      cycle_length = rotation_length(exercises, pattern)

      windows
      |> Enum.with_index(1)
      |> Enum.map(fn {window_seconds, round} ->
        segment(
          section,
          :countdown,
          window_seconds,
          round,
          total_rounds,
          round_exercises_for_emom(exercises, round, cycle_length),
          text("minute", %{round: round})
        )
      end)
    end
  end

  # Window lengths that fill `duration`, cycling the pattern; the final window is
  # clamped to whatever time remains.
  defp emom_windows(duration, pattern) when duration > 0 do
    pattern
    |> Stream.cycle()
    |> Enum.reduce_while({[], 0}, fn window, {acc, used} ->
      if used >= duration do
        {:halt, {acc, used}}
      else
        length = min(window, duration - used)
        {:cont, {[length | acc], used + length}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp emom_windows(_duration, [window | _rest]), do: [window]

  defp interval_pattern(section) do
    case get_timer_field(section, :interval_pattern_seconds) do
      [_ | _] = pattern ->
        if Enum.all?(pattern, &(is_integer(&1) and &1 > 0)), do: pattern

      _ ->
        nil
    end
  end

  # Exercises assigned to minute N of a rotation repeat every `cycle_length`
  # windows: the pattern length when one is authored, otherwise the highest
  # assignment (3 exercises assigned 1..3 rotate every 3 minutes).
  defp rotation_length(_exercises, [_ | _] = pattern), do: length(pattern)

  defp rotation_length(exercises, _pattern) do
    exercises
    |> Enum.map(&(&1[:interval_assignment] || &1["interval_assignment"]))
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.max(fn -> 1 end)
  end

  defp round_exercises_for_emom(exercises, round, cycle_length) do
    slot = rem(round - 1, cycle_length) + 1

    Enum.filter(exercises, fn ex ->
      case ex[:interval_assignment] || ex["interval_assignment"] do
        nil -> true
        assignment -> assignment == slot
      end
    end)
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

      label =
        if rem(round, 2) == 1,
          do: text("odd_minute", %{round: round}),
          else: text("even_minute", %{round: round})

      segment(
        section,
        :countdown,
        interval_duration(duration, interval, round),
        round,
        total_rounds,
        round_exercises,
        label
      )
    end)
  end

  # ── Billat: work/rest cycles ─────────────────────────────────────────────────

  defp build_billat_segments(section, exercises) do
    work = get_timer_field(section, :work_seconds) || 0
    rest = get_timer_field(section, :rest_seconds) || 0
    cycles = get_timer_field(section, :cycles) || 1

    work_rest_segments(section, exercises, work, rest, cycles)
  end

  # ── Tabata / Custom HIIT ─────────────────────────────────────────────────────

  defp build_tabata_segments(section, exercises) do
    work = get_timer_field(section, :work_seconds) || 20
    rest = get_timer_field(section, :rest_seconds) || 10
    rounds = get_timer_field(section, :rounds) || 8

    work_rest_segments(section, exercises, work, rest, rounds)
  end

  # Work/rest pairs without a trailing rest after the final work interval.
  defp work_rest_segments(section, exercises, work, rest, rounds) do
    Enum.flat_map(1..rounds, fn round ->
      work_segment =
        segment(
          section,
          :countdown,
          work,
          round,
          rounds,
          exercises,
          text("work", %{round: round, total: rounds})
        )

      if round < rounds do
        [
          work_segment,
          segment(
            section,
            :countdown,
            rest,
            round,
            rounds,
            [],
            [phase: "rest"] ++ text("rest_round", %{round: round, total: rounds})
          )
        ]
      else
        [work_segment]
      end
    end)
  end

  # ── Cluster: clusters separated by intra-set rest, sets by full rest ─────────

  defp build_cluster_segments(section, exercises) do
    sets = positive(get_timer_field(section, :sets)) || 1
    intra_rest = positive(get_timer_field(section, :intra_rest_seconds))
    clusters = positive(get_timer_field(section, :cluster_reps)) || 1
    set_rest = positive(get_timer_field(section, :rest_seconds))

    if clusters > 1 do
      Enum.flat_map(1..sets, fn set_num ->
        set_segments =
          with_rests(1..clusters, intra_rest, fn cluster ->
            segment(
              section,
              :manual,
              nil,
              set_num,
              sets,
              exercises,
              text("cluster", %{set: set_num, total: sets, cluster: cluster, clusters: clusters})
            )
          end)

        rest_between_sets(section, set_segments, set_num, sets, set_rest || intra_rest)
      end)
    else
      # Without clusters per set, each set is one cluster separated by intra rest.
      with_rests(1..sets, set_rest || intra_rest, fn set_num ->
        segment(
          section,
          :manual,
          nil,
          set_num,
          sets,
          exercises,
          text("set", %{set: set_num, total: sets})
        )
      end)
    end
  end

  defp rest_between_sets(_section, set_segments, set_num, sets, _rest) when set_num == sets,
    do: set_segments

  defp rest_between_sets(_section, set_segments, _set_num, _sets, nil), do: set_segments

  defp rest_between_sets(section, set_segments, set_num, sets, rest),
    do: set_segments ++ [rest_segment(section, rest, set_num, sets, text("rest"))]

  # ── HRR: effort then HR recovery period ──────────────────────────────────────

  defp build_hrr_segments(section, exercises) do
    effort = get_timer_field(section, :effort_seconds) || 0
    hr_zone = get_timer_field(section, :hr_zone)
    effort_label = if hr_zone, do: text("effort_zone", %{zone: hr_zone}), else: text("effort")
    drop = positive(get_timer_field(section, :hr_drop_target))
    recovery_label = if drop, do: text("recover_drop", %{bpm: drop}), else: text("recover")

    recovery =
      case {positive(get_timer_field(section, :rest_seconds)),
            positive(get_timer_field(section, :recovery_cap_seconds))} do
        {rest, _cap} when is_integer(rest) ->
          segment(section, :countdown, rest, nil, nil, [], [phase: "rest"] ++ recovery_label)

        {nil, cap} ->
          segment(section, :countup, cap, nil, nil, [], [phase: "rest"] ++ recovery_label)
      end

    [
      segment(section, :countdown, effort, nil, nil, exercises, effort_label),
      recovery
    ]
  end

  # Builds one work segment per item with a rest countdown between them (never
  # after the last one). A nil rest emits no rest segments.
  defp with_rests(range, rest, work_fun) do
    count = Enum.count(range)

    Enum.flat_map(range, fn index ->
      work_segment = work_fun.(index)

      if rest && index < count,
        do: [work_segment, rest_after(work_segment, rest)],
        else: [work_segment]
    end)
  end

  defp rest_after(work_segment, rest) do
    Map.merge(work_segment, %{
      kind: :countdown,
      duration_seconds: rest,
      exercises: [],
      label: "Rest",
      label_key: "rest",
      label_params: %{},
      phase: "rest"
    })
  end

  defp rest_segment(section, rest, round, total_rounds, label) do
    segment(section, :countdown, rest, round, total_rounds, [], [phase: "rest"] ++ label)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Labels travel as a stable key plus parameters so clients can localize
  # them; `label` keeps an English rendering for older clients and logs.
  @label_texts %{
    "transition" => "Transition",
    "rest" => "Rest",
    "kcal_target" => "{kcal} kcal",
    "kcal_target_open" => "Kcal target",
    "death_by" => "Death By",
    "emom" => "EMOM",
    "round" => "Round {round}/{total}",
    "set" => "Set {set}/{total}",
    "minute" => "Min {round}",
    "odd_minute" => "Odd – Min {round}",
    "even_minute" => "Even – Min {round}",
    "work" => "Work {round}/{total}",
    "rest_round" => "Rest {round}/{total}",
    "cluster" => "Set {set}/{total} · Cluster {cluster}/{clusters}",
    "effort" => "Effort",
    "effort_zone" => "Effort (Zone {zone})",
    "recover" => "Recover to HR",
    "recover_drop" => "Recover −{bpm} bpm"
  }

  @doc "The label keys segments can carry, for contract tests and clients."
  def label_keys, do: Map.keys(@label_texts)

  defp text(key, params \\ %{}) do
    english =
      Enum.reduce(params, Map.fetch!(@label_texts, key), fn {name, value}, acc ->
        String.replace(acc, "{#{name}}", to_string(value))
      end)

    [label: english, label_key: key, label_params: params]
  end

  defp segment(section, kind, duration, round, total_rounds, exercises, opts \\ []) do
    id = section[:id] || section["id"]
    name = section[:name] || section["name"] || ""
    format = section_format(section)
    scoreable = section[:scoreable] || section["scoreable"] || false
    score_config = section[:score_config] || section["score_config"]
    label = Keyword.get(opts, :label, name)
    label_key = Keyword.get(opts, :label_key)
    label_params = Keyword.get(opts, :label_params, %{})
    phase = Keyword.get(opts, :phase, "work")

    %{
      segment_key: nil,
      section_id: id,
      section_name: name,
      format: format,
      kind: kind,
      phase: phase,
      duration_seconds: duration,
      round: round,
      total_rounds: total_rounds,
      label: label,
      label_key: label_key,
      label_params: label_params,
      exercises: exercises,
      section_note: section[:note] || section["note"],
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

  defp metadata(section, key) do
    metadata = section[:section_metadata] || section["section_metadata"] || %{}

    Enum.find_value(metadata, fn {metadata_key, value} ->
      if to_string(metadata_key) == key, do: value
    end)
  end

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

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

  defp flatten_nested_sections(sections) do
    sections
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {section, index} ->
      flatten_nested_section(section, nil, Integer.to_string(index))
    end)
  end

  defp flatten_nested_section(section, parent_id, path) do
    id = value(section, :id) || "draft-section-#{path}"
    children = value(section, :sections, [])

    normalized =
      section
      |> Map.delete(:sections)
      |> Map.delete("sections")
      |> put_value(:id, id)
      |> put_value(:parent_section_id, parent_id)

    nested =
      children
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {child, index} ->
        flatten_nested_section(child, id, "#{path}.#{index}")
      end)

    [normalized | nested]
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp put_value(map, key, value) do
    map
    |> Map.delete(Atom.to_string(key))
    |> Map.put(key, value)
  end
end
