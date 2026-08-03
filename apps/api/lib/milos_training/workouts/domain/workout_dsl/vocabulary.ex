defmodule MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary do
  @moduledoc """
  Versioned canonical vocabulary shared by parsing, formatting, validation,
  templates, documentation, and autocomplete.

  Internal identifiers use snake_case. DSL tokens use kebab-case.
  """

  alias MilosTraining.Workouts.Domain.WorkoutAuthoringMetadata
  alias MilosTraining.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  @timer_specs %{
    "untimed" => %{
      required: [],
      optional: [],
      dsl_required: [],
      body: "ordered",
      scores: ~w(load reps weight pass_fail)
    },
    "for_time" => %{
      required: [],
      optional: [:rounds, :time_cap_seconds, :transition_seconds],
      dsl_required: [],
      body: "work-sequence",
      scores: ~w(time)
    },
    "train_to_exhaustion" => %{
      required: [],
      optional: [:rest_seconds, :rounds, :time_cap_seconds],
      dsl_required: [],
      body: "work-sequence",
      scores: ~w(reps rounds intervals_survived)
    },
    "kcal_target" => %{
      required: [],
      optional: [:kcal_target, :time_cap_seconds],
      dsl_required: [:kcal_target],
      body: "energy-target",
      scores: ~w(time kcal)
    },
    "emom" => %{
      required: [:duration_seconds, :interval_seconds],
      optional: [:scoring_mode, :max_windows, :transition_seconds],
      dsl_required: [:duration_seconds, :interval_seconds],
      body: "interval-slots",
      scores: ~w(reps rounds pass_fail)
    },
    "complex_emom" => %{
      required: [:duration_seconds, :interval_seconds],
      optional: [:scoring_mode, :amrap_scoring_style, :max_windows, :transition_seconds],
      dsl_required: [:duration_seconds, :interval_seconds],
      body: "interval-slots",
      scores: ~w(reps rounds rounds+reps)
    },
    "even_odd" => %{
      required: [:duration_seconds],
      optional: [:interval_seconds, :transition_seconds],
      dsl_required: [:duration_seconds],
      body: "even-odd-slots",
      scores: ~w(reps rounds pass_fail)
    },
    "billat" => %{
      required: [:work_seconds, :rest_seconds, :cycles],
      optional: [:target_distance_meters, :target_pace, :transition_seconds],
      dsl_required: [:work_seconds, :rest_seconds, :cycles],
      body: "work-rest-cycles",
      scores: ~w(intervals_survived accumulated_work_time distance)
    },
    "amrap" => %{
      required: [:duration_seconds],
      optional: [:target_rounds, :transition_seconds],
      dsl_required: [:duration_seconds],
      body: "repeating-work-sequence",
      scores: ~w(rounds rounds+reps reps)
    },
    "edt" => %{
      required: [:duration_seconds],
      optional: [:pr_zone_rounds, :transition_seconds],
      dsl_required: [:duration_seconds],
      body: "paired-work",
      scores: ~w(reps rounds)
    },
    "death_by" => %{
      required: [:start_reps, :step_reps],
      optional: [:ladder_cap, :interval_seconds],
      dsl_required: [:start_reps, :step_reps],
      body: "incrementing-interval",
      scores: ~w(intervals_survived reps)
    },
    "tabata" => %{
      required: [:work_seconds, :rest_seconds, :rounds],
      optional: [:transition_seconds],
      dsl_required: [:work_seconds, :rest_seconds, :rounds],
      body: "work-rest-stations",
      scores: ~w(reps pass_fail)
    },
    "custom_hiit" => %{
      required: [:work_seconds, :rest_seconds, :rounds],
      optional: [:transition_seconds],
      dsl_required: [:work_seconds, :rest_seconds, :rounds],
      body: "work-rest-stations",
      scores: ~w(reps rounds pass_fail)
    },
    "cluster" => %{
      required: [:intra_rest_seconds, :sets],
      optional: [:cluster_reps, :rest_seconds],
      dsl_required: [:intra_rest_seconds, :sets],
      body: "cluster-sets",
      scores: ~w(load reps)
    },
    "hrr" => %{
      required: [:effort_seconds],
      optional: [:hr_zone, :rest_seconds, :recovery_cap_seconds, :hr_drop_target],
      dsl_required: [:effort_seconds],
      body: "effort-recovery",
      scores: ~w(hr_drop time)
    },
    "ladder_ascending" => %{
      required: [:start_reps, :step_reps],
      optional: [:ladder_cap, :time_cap_seconds, :end_reps],
      dsl_required: [:start_reps, :step_reps],
      body: "ascending-ladder",
      scores: ~w(time reps rounds)
    },
    "ladder_descending" => %{
      required: [:start_reps, :step_reps, :min_reps],
      optional: [:time_cap_seconds],
      dsl_required: [:start_reps, :step_reps, :min_reps],
      body: "descending-ladder",
      scores: ~w(time reps rounds)
    },
    "pyramid" => %{
      required: [:peak_reps, :step_reps],
      optional: [:start_reps, :time_cap_seconds],
      dsl_required: [:peak_reps, :step_reps],
      body: "pyramid",
      scores: ~w(time reps rounds)
    },
    "rest" => %{
      required: [],
      optional: [:duration_seconds, :recovery_condition],
      dsl_required: [],
      body: "recovery",
      scores: []
    }
  }

  @section_formats [
    "untimed",
    "for_time",
    "train_to_exhaustion",
    "kcal_target",
    "emom",
    "complex_emom",
    "even_odd",
    "billat",
    "amrap",
    "edt",
    "death_by",
    "tabata",
    "custom_hiit",
    "cluster",
    "hrr",
    "ladder_ascending",
    "ladder_descending",
    "pyramid",
    "rest"
  ]

  @format_aliases %{
    "straight_sets" => {"untimed", "straight_sets"},
    "rounds" => {"untimed", "rounds"},
    "circuit" => {"untimed", "circuit"},
    "stations" => {"untimed", "stations"},
    "recovery" => {"rest", nil}
  }

  @timer_dsl_keys %{
    "duration" => :duration_seconds,
    "interval" => :interval_seconds,
    "time-cap" => :time_cap_seconds,
    "work" => :work_seconds,
    "rest" => :rest_seconds,
    "rounds" => :rounds,
    "sets" => :sets,
    "cycles" => :cycles,
    "intra-set-rest" => :intra_rest_seconds,
    "effort-duration" => :effort_seconds,
    "start-reps" => :start_reps,
    "step-reps" => :step_reps,
    "minimum-reps" => :min_reps,
    "end-reps" => :end_reps,
    "peak-reps" => :peak_reps,
    "ladder-cap" => :ladder_cap,
    "calorie-target" => :kcal_target,
    "pr-zone-rounds" => :pr_zone_rounds,
    "maximum-windows" => :max_windows,
    "target-rounds" => :target_rounds,
    "cluster-reps" => :cluster_reps,
    "scoring-mode" => :scoring_mode,
    "amrap-scoring-style" => :amrap_scoring_style,
    "heart-rate-zone" => :hr_zone,
    "heart-rate-drop-target" => :hr_drop_target,
    "recovery-cap" => :recovery_cap_seconds,
    "recovery-condition" => :recovery_condition,
    "target-distance" => :target_distance_meters,
    "target-pace" => :target_pace,
    "transition-time" => :transition_seconds
  }

  @workout_keys ~w(
    dsl-version title subtitle description type difficulty estimated-duration
    equipment tags target-population objective location modality
    program-position default-scale is-team-workout source-revision
    canonical-schema-version
  )

  @section_keys ~w(
    title subtitle score score-unit score-label composition
    rest-between-exercises rest-between-rounds rest-between-groups
    rest-before-next-section transition-time auto-advance recovery-condition
    target-condition
  )

  @exercise_keys ~w(
    subtitle sets reps duration calories distance load load-mode percentage-of
    target-rpe target-rir tempo pace cadence target-heart-rate side stance
    grip range-of-motion height incline resistance equipment variation
    interval-assignment score-contribution transition-time
    rest-between-reps rest-within-cluster rest-between-sets
    rest-between-exercises rest-between-rounds rest-between-groups
    rest-between-sides rest-after-exercise rest-until rest-range
    progression load-start load-step prescription excluded
  )

  @group_keys ~w(title sets rest-between-groups)
  @scale_keys @exercise_keys
  @note_markers Enum.map(WorkoutAuthoringMetadata.note_types(), &"!#{&1}")
  @key_aliases %{"set" => "sets"}

  def section_formats, do: @section_formats
  def format_aliases, do: @format_aliases

  def resolve_format(format) do
    normalized = normalize_format(format)

    cond do
      normalized in @section_formats ->
        {:ok, normalized, nil}

      Map.has_key?(@format_aliases, normalized) ->
        {canonical, composition} = Map.fetch!(@format_aliases, normalized)
        {:ok, canonical, composition}

      true ->
        {:error, :unknown_format}
    end
  end

  def valid_section_format?(format),
    do: match?({:ok, _canonical, _composition}, resolve_format(format))

  def normalize_format(format) when is_atom(format),
    do: format |> Atom.to_string() |> normalize_format()

  def normalize_format(format) when is_binary(format) do
    format
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
  end

  def normalize_format(_format), do: nil

  def dsl_format(format) when is_binary(format), do: String.replace(format, "_", "-")

  def format_spec(format) do
    with {:ok, canonical, _composition} <- resolve_format(format) do
      Map.get(@timer_specs, canonical)
    else
      _ -> nil
    end
  end

  def required_timer_fields(format), do: spec_list(format, :required)
  def required_dsl_timer_fields(format), do: spec_list(format, :dsl_required)
  def optional_timer_fields(format), do: spec_list(format, :optional)

  def allowed_timer_fields(format),
    do: Enum.uniq(required_timer_fields(format) ++ optional_timer_fields(format))

  def allowed_score_types(format) do
    case format_spec(format) do
      nil -> []
      spec -> spec.scores
    end
  end

  def timer_field_for_dsl_key(key), do: Map.get(@timer_dsl_keys, canonical_key(key))

  def dsl_key_for_timer_field(field) do
    Enum.find_value(@timer_dsl_keys, fn {key, candidate} ->
      if candidate == field, do: key
    end)
  end

  def timer_value_kind(field)
      when field in [
             :duration_seconds,
             :interval_seconds,
             :time_cap_seconds,
             :work_seconds,
             :rest_seconds,
             :intra_rest_seconds,
             :effort_seconds,
             :transition_seconds,
             :recovery_cap_seconds
           ],
      do: :duration

  def timer_value_kind(:target_distance_meters), do: :distance

  def timer_value_kind(field)
      when field in [
             :rounds,
             :cycles,
             :start_reps,
             :step_reps,
             :min_reps,
             :end_reps,
             :peak_reps,
             :ladder_cap,
             :kcal_target,
             :pr_zone_rounds,
             :max_windows,
             :target_rounds,
             :cluster_reps,
             :sets,
             :hr_zone,
             :hr_drop_target
           ],
      do: :integer

  def timer_value_kind(field) when field in [:scoring_mode, :amrap_scoring_style],
    do: :enum

  def timer_value_kind(_field), do: :string

  def timer_enum_values(:scoring_mode), do: ~w(for_time for_quality amrap to_failure)
  def timer_enum_values(:amrap_scoring_style), do: ~w(grand_total lowest_window)
  def timer_enum_values(_field), do: []

  def suggestions(:workout), do: @workout_keys ++ @note_markers
  def suggestions(:section), do: suggestions(:section, nil)
  def suggestions(:exercise), do: @exercise_keys ++ @note_markers
  def suggestions(:header), do: ~w(title subtitle) ++ @note_markers
  def suggestions(:group), do: @group_keys ++ @note_markers
  def suggestions(:scale), do: @scale_keys ++ @note_markers
  def suggestions(:note), do: @note_markers
  def suggestions(_scope), do: []

  def suggestions(:section, nil), do: @section_keys ++ @note_markers

  def suggestions(:section, format) do
    timer_keys =
      format
      |> allowed_timer_fields()
      |> Enum.map(&dsl_key_for_timer_field/1)
      |> Enum.reject(&is_nil/1)

    Enum.uniq(@section_keys ++ timer_keys ++ @note_markers)
  end

  def workout_key?(key), do: canonical_key(key) in @workout_keys
  def section_key?(key), do: canonical_key(key) in @section_keys
  def exercise_key?(key), do: canonical_key(key) in @exercise_keys
  def group_key?(key), do: canonical_key(key) in @group_keys
  def note_marker?(marker), do: marker in @note_markers
  def note_markers, do: @note_markers

  def export do
    %{
      version: 1,
      section_formats: @section_formats,
      format_aliases:
        Map.new(@format_aliases, fn {alias_name, {format, composition}} ->
          {dsl_format(alias_name),
           %{
             format: dsl_format(format),
             composition: composition && dsl_format(composition)
           }}
        end),
      format_specs:
        Map.new(@section_formats, fn format ->
          spec = Map.fetch!(@timer_specs, format)

          {format,
           %{
             required: Enum.map(spec.dsl_required, &dsl_key_for_timer_field/1),
             optional: Enum.map(spec.optional, &dsl_key_for_timer_field/1),
             body: spec.body,
             score_types: spec.scores
           }}
        end),
      workout_parameters: suggestions(:workout),
      exercise_parameters: suggestions(:exercise),
      group_parameters: suggestions(:group),
      scale_parameters: suggestions(:scale),
      header_parameters: suggestions(:header),
      note_markers: @note_markers,
      section_parameters:
        Map.new(@section_formats, fn format ->
          {format, suggestions(:section, format)}
        end),
      exercise_catalog: ExerciseCatalog.export()
    }
  end

  def canonical_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.downcase()
    |> String.replace("_", "-")
    |> then(&Map.get(@key_aliases, &1, &1))
  end

  defp spec_list(format, key) do
    case format_spec(format) do
      nil -> []
      spec -> Map.fetch!(spec, key)
    end
  end
end
