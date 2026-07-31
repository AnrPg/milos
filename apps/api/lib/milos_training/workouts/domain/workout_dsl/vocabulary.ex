defmodule MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary do
  @moduledoc """
  Versioned canonical vocabulary shared by workout DSL parsing, formatting,
  validation, help, and autocomplete.

  Internal timer identifiers use snake_case because they are persisted and
  consumed by the existing workout domain. The textual DSL emits kebab-case.
  """

  @timer_specs %{
    "untimed" => %{required: [], optional: []},
    "for_time" => %{required: [], optional: [:time_cap_seconds]},
    "train_to_exhaustion" => %{required: [], optional: [:rest_seconds]},
    "kcal_target" => %{required: [], optional: [:kcal_target, :time_cap_seconds]},
    "emom" => %{
      required: [:duration_seconds, :interval_seconds],
      optional: [:scoring_mode, :max_windows]
    },
    "complex_emom" => %{
      required: [:duration_seconds, :interval_seconds],
      optional: [:scoring_mode, :amrap_scoring_style, :max_windows]
    },
    "even_odd" => %{required: [:duration_seconds], optional: []},
    "billat" => %{required: [:work_seconds, :rest_seconds, :cycles], optional: []},
    "amrap" => %{required: [:duration_seconds], optional: []},
    "edt" => %{required: [:duration_seconds], optional: [:pr_zone_rounds]},
    "death_by" => %{required: [:start_reps, :step_reps], optional: [:ladder_cap]},
    "tabata" => %{
      required: [:work_seconds, :rest_seconds, :rounds],
      optional: []
    },
    "custom_hiit" => %{
      required: [:work_seconds, :rest_seconds, :rounds],
      optional: []
    },
    "cluster" => %{required: [:intra_rest_seconds, :sets], optional: []},
    "hrr" => %{required: [:effort_seconds], optional: [:hr_zone]},
    "ladder_ascending" => %{
      required: [:start_reps, :step_reps],
      optional: [:ladder_cap]
    },
    "ladder_descending" => %{
      required: [:start_reps, :step_reps, :min_reps],
      optional: []
    },
    "pyramid" => %{required: [:peak_reps, :step_reps], optional: []},
    "rest" => %{required: [:duration_seconds], optional: []}
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

  @timer_dsl_keys %{
    "duration" => :duration_seconds,
    "interval" => :interval_seconds,
    "time-cap" => :time_cap_seconds,
    "work" => :work_seconds,
    "rest" => :rest_seconds,
    "rounds" => :rounds,
    "cycles" => :cycles,
    "intra-set-rest" => :intra_rest_seconds,
    "effort-duration" => :effort_seconds,
    "start-reps" => :start_reps,
    "step-reps" => :step_reps,
    "minimum-reps" => :min_reps,
    "peak-reps" => :peak_reps,
    "ladder-cap" => :ladder_cap,
    "calorie-target" => :kcal_target,
    "pr-zone-rounds" => :pr_zone_rounds,
    "maximum-windows" => :max_windows,
    "scoring-mode" => :scoring_mode,
    "amrap-scoring-style" => :amrap_scoring_style,
    "heart-rate-zone" => :hr_zone
  }

  @exercise_keys ~w(
    sets reps duration calories load tempo interval-assignment
    rest-between-sets progression
  )

  @note_markers ~w(
    !note !coach-note !athlete-note !safety-note !scaling-note !equipment-note
  )

  def section_formats, do: @section_formats

  def valid_section_format?(format), do: normalize_format(format) in @section_formats

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

  def required_timer_fields(format) do
    @timer_specs
    |> Map.get(normalize_format(format), %{required: []})
    |> Map.fetch!(:required)
  end

  def optional_timer_fields(format) do
    @timer_specs
    |> Map.get(normalize_format(format), %{optional: []})
    |> Map.fetch!(:optional)
  end

  def allowed_timer_fields(format),
    do: required_timer_fields(format) ++ optional_timer_fields(format)

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
             :effort_seconds
           ],
      do: :duration

  def timer_value_kind(field)
      when field in [
             :rounds,
             :cycles,
             :start_reps,
             :step_reps,
             :min_reps,
             :peak_reps,
             :ladder_cap,
             :kcal_target,
             :pr_zone_rounds,
             :max_windows,
             :hr_zone
           ],
      do: :integer

  def timer_value_kind(_field), do: :string

  def suggestions(:workout),
    do: ~w(dsl-version title subtitle type is-team-workout) ++ @note_markers

  def suggestions(:section), do: suggestions(:section, nil)
  def suggestions(:exercise), do: @exercise_keys ++ @note_markers
  def suggestions(:header), do: ~w(title subtitle) ++ @note_markers
  def suggestions(:note), do: @note_markers
  def suggestions(_scope), do: []

  def suggestions(:section, nil),
    do: ~w(title subtitle score score-unit rest-before-next-section) ++ @note_markers

  def suggestions(:section, format) do
    timer_keys =
      format
      |> allowed_timer_fields()
      |> Enum.map(&dsl_key_for_timer_field/1)
      |> Enum.reject(&is_nil/1)

    Enum.uniq(
      ~w(title subtitle score score-unit rest-before-next-section) ++
        timer_keys ++ @note_markers
    )
  end

  def exercise_key?(key), do: canonical_key(key) in @exercise_keys
  def note_marker?(marker), do: marker in @note_markers

  def export do
    %{
      version: 1,
      section_formats: @section_formats,
      workout_parameters: suggestions(:workout),
      exercise_parameters: suggestions(:exercise),
      header_parameters: suggestions(:header),
      note_markers: @note_markers,
      section_parameters:
        Map.new(@section_formats, fn format ->
          {format, suggestions(:section, format)}
        end)
    }
  end

  def canonical_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.downcase()
    |> String.replace("_", "-")
  end
end
