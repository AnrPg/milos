defmodule MilosTraining.Workouts.Domain.WorkoutDsl.Formatter do
  @moduledoc false

  alias MilosTraining.Workouts.Domain.WorkoutDsl.{Values, Vocabulary}

  @version 1

  def format(workout, opts \\ []) when is_map(workout) do
    version = Keyword.get(opts, :version, @version)
    metadata = value(workout, :workout_metadata, %{})

    [
      "[workout]",
      "dsl-version: #{version}",
      scalar_line("canonical-schema-version", value(metadata, "schema_version", 1)),
      scalar_line("source-revision", value(metadata, "source_revision")),
      scalar_line("title", value(workout, :title)),
      scalar_line("subtitle", value(workout, :subtitle)),
      scalar_line("description", value(workout, :description)),
      scalar_line("type", value(workout, :type)),
      scalar_line("difficulty", value(workout, :difficulty)),
      duration_line("estimated-duration", value(workout, :estimated_duration_seconds)),
      list_line("equipment", value(workout, :equipment, [])),
      list_line("tags", value(workout, :tags, [])),
      scalar_line("target-population", value(metadata, "target_population")),
      scalar_line("objective", value(metadata, "objective")),
      scalar_line("location", value(metadata, "location")),
      scalar_line("modality", value(metadata, "modality")),
      scalar_line("program-position", value(metadata, "program_position")),
      scalar_line("default-scale", value(metadata, "default_scale")),
      boolean_line("is-team-workout", value(workout, :is_team_workout)),
      format_notes(workout),
      workout
      |> value(:sections, [])
      |> Enum.sort_by(&value(&1, :order, 0))
      |> Enum.map(&format_section/1),
      "[/workout]"
    ]
    |> flatten_lines()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp format_section(section) do
    timer_config = value(section, :timer_config, %{})
    format = value(timer_config, :type, "untimed") |> to_string()
    metadata = value(section, :section_metadata, %{})

    timer_lines =
      format
      |> Vocabulary.allowed_timer_fields()
      |> Enum.map(fn field ->
        case value(timer_config, field) do
          nil -> nil
          timer_value -> format_timer_line(field, timer_value)
        end
      end)

    [
      "[section: #{Vocabulary.dsl_format(format)}]",
      scalar_line("title", value(section, :name)),
      scalar_line("subtitle", value(section, :subtitle)),
      scalar_line("composition", metadata |> value("composition") |> dsl_enum()),
      timer_lines,
      format_score(section),
      duration_line(
        "rest-between-exercises",
        value(metadata, "rest_between_exercises_seconds")
      ),
      duration_line("rest-between-rounds", value(metadata, "rest_between_rounds_seconds")),
      duration_line("rest-between-groups", value(metadata, "rest_between_groups_seconds")),
      duration_line("transition-time", value(metadata, "transition_seconds")),
      boolean_line("auto-advance", value(metadata, "auto_advance")),
      scalar_line("recovery-condition", value(metadata, "recovery_condition")),
      scalar_line("target-condition", value(metadata, "target_condition")),
      duration_line(
        "rest-before-next-section",
        value(section, :rest_before_next_section_seconds)
      ),
      format_notes(section),
      format_section_items(value(section, :exercises, [])),
      section
      |> value(:sections, [])
      |> Enum.sort_by(&value(&1, :order, 0))
      |> Enum.map(&format_section/1),
      "[/section]"
    ]
    |> flatten_lines()
  end

  defp format_section_items(items) do
    items
    |> Enum.sort_by(&value(&1, :order, 0))
    |> Enum.chunk_by(&group_identity/1)
    |> Enum.map(fn items ->
      case items do
        [item] ->
          if is_nil(group_identity(item)),
            do: format_item(item),
            else: format_group_or_items(items)

        group_items ->
          format_group_or_items(group_items)
      end
    end)
  end

  defp format_group_or_items(items) do
    case group_identity(hd(items)) do
      nil ->
        Enum.map(items, &format_item/1)

      {_type, _id} ->
        config = value(hd(items), :group_config, %{})
        type = value(config, "type") || group_type_from_item(hd(items))

        [
          "[group: #{dsl_enum(type)}]",
          scalar_line("title", value(config, "title")),
          scalar_line("sets", value(config, "sets")),
          duration_line(
            "rest-between-groups",
            value(config, "rest_between_groups_seconds")
          ),
          format_notes(%{notes: value(config, "notes", [])}),
          Enum.map(items, &format_exercise/1),
          "[/group]"
        ]
        |> flatten_lines()
    end
  end

  defp format_item(item) do
    if to_string(value(item, :item_type, "exercise")) == "header" do
      [
        "[header]",
        scalar_line("title", value(item, :name)),
        scalar_line("subtitle", value(item, :subtitle)),
        format_notes(item),
        "[/header]"
      ]
      |> flatten_lines()
    else
      format_exercise(item)
    end
  end

  defp format_exercise(item) do
    metadata = value(item, :prescription_metadata, %{})

    [
      "[exercise: #{format_scalar(value(item, :name))}]",
      scalar_line("subtitle", value(item, :subtitle)),
      format_prescription(item),
      scalar_line("tempo", value(item, :tempo)),
      number_line("target-rpe", value(metadata, "target_rpe")),
      scalar_line("target-rir", value(metadata, "target_rir")),
      scalar_line("percentage-of", value(metadata, "percentage_of")),
      scalar_line("pace", value(metadata, "pace")),
      scalar_line("cadence", value(metadata, "cadence")),
      bpm_line("target-heart-rate", value(metadata, "target_heart_rate_bpm")),
      scalar_line("side", value(metadata, "side")),
      scalar_line("stance", value(metadata, "stance")),
      scalar_line("grip", value(metadata, "grip")),
      scalar_line("range-of-motion", value(metadata, "range_of_motion")),
      unit_line("height", value(metadata, "height_cm"), "cm"),
      unit_line("incline", value(metadata, "incline_percent"), "%"),
      scalar_line("resistance", value(metadata, "resistance")),
      list_line("equipment", value(metadata, "equipment", [])),
      scalar_line("variation", value(metadata, "variation")),
      scalar_line("score-contribution", value(metadata, "score_contribution")),
      scalar_line("interval-assignment", format_interval(value(item, :interval_assignment))),
      duration_line("rest-between-reps", value(metadata, "rest_between_reps_seconds")),
      duration_line("rest-within-cluster", value(item, :cluster_rest_seconds)),
      duration_line("rest-between-sets", value(item, :rest_seconds)),
      duration_line(
        "rest-between-exercises",
        value(metadata, "rest_between_exercises_seconds")
      ),
      duration_line("rest-between-rounds", value(metadata, "rest_between_rounds_seconds")),
      duration_line("rest-between-groups", value(metadata, "rest_between_groups_seconds")),
      duration_line("rest-between-sides", value(metadata, "rest_between_sides_seconds")),
      duration_line("rest-after-exercise", value(item, :rest_pause_seconds)),
      scalar_line("rest-until", value(metadata, "rest_until")),
      duration_range_line("rest-range", value(metadata, "rest_range_seconds")),
      duration_line("transition-time", value(metadata, "transition_seconds")),
      format_notes(item),
      item |> value(:variations, []) |> Enum.map(&format_scale/1),
      "[/exercise]"
    ]
    |> flatten_lines()
  end

  defp format_scale(variation) do
    metadata = value(variation, :prescription_metadata, %{})

    [
      "[scale: #{value(variation, :scale_level_slug)}]",
      boolean_line("excluded", value(variation, :excluded)),
      scalar_line("variation", value(variation, :exercise_name_override)),
      format_prescription(variation),
      scalar_line("tempo", value(variation, :tempo)),
      number_line("target-rpe", value(metadata, "target_rpe")),
      scalar_line("target-rir", value(metadata, "target_rir")),
      scalar_line("pace", value(metadata, "pace")),
      scalar_line("cadence", value(metadata, "cadence")),
      bpm_line("target-heart-rate", value(metadata, "target_heart_rate_bpm")),
      scalar_line("side", value(metadata, "side")),
      scalar_line("stance", value(metadata, "stance")),
      scalar_line("grip", value(metadata, "grip")),
      scalar_line("range-of-motion", value(metadata, "range_of_motion")),
      unit_line("height", value(metadata, "height_cm"), "cm"),
      unit_line("incline", value(metadata, "incline_percent"), "%"),
      scalar_line("resistance", value(metadata, "resistance")),
      list_line("equipment", value(metadata, "equipment", [])),
      duration_line("rest-between-reps", value(metadata, "rest_between_reps_seconds")),
      duration_line("rest-between-sets", value(variation, :rest_seconds)),
      duration_line("rest-between-sides", value(metadata, "rest_between_sides_seconds")),
      scalar_line("rest-until", value(metadata, "rest_until")),
      duration_range_line("rest-range", value(metadata, "rest_range_seconds")),
      format_notes(variation),
      "[/scale]"
    ]
    |> flatten_lines()
  end

  defp format_prescription(item) do
    progression = value(item, :load_progression)
    prescriptions = value(item, :set_prescriptions, [])

    cond do
      linear_progression?(progression) ->
        [
          "progression: linear",
          scalar_line("sets", value(item, :sets)),
          prescription_dimension_line(item),
          load_line(
            "load-start",
            value(progression, "start_value"),
            value(progression, "start_mode"),
            metadata_value(item, "load_unit")
          ),
          signed_load_step_line(
            progression,
            metadata_value(item, "load_unit")
          )
        ]

      prescriptions != [] and not uniform_prescriptions?(prescriptions) ->
        [
          "progression: explicit",
          "sets:",
          Enum.map(prescriptions, &format_set/1)
        ]

      true ->
        {load_value, load_mode, load_unit} = display_load(item)

        [
          scalar_line("sets", value(item, :sets)),
          prescription_dimension_line(item),
          load_line(
            "load",
            load_value,
            load_mode,
            load_unit
          )
        ]
    end
  end

  defp format_set(set) do
    amount =
      case to_string(value(set, :prescription_unit, "reps")) do
        "reps" -> "#{value(set, :prescription_value)} reps"
        "secs" -> "#{value(set, :prescription_value)} sec"
        "kcal" -> "#{value(set, :prescription_value)} kcal"
        "meters" -> Values.format_distance(value(set, :prescription_value))
      end

    metadata = value(set, :metadata, %{})

    load =
      case value(set, :load_value) do
        nil ->
          nil

        load_value ->
          " @ " <>
            Values.format_load(
              load_value,
              value(set, :load_mode),
              value(metadata, "load_unit")
            )
      end

    extras =
      [
        scalar_fragment("tempo", value(metadata, "tempo")),
        scalar_fragment("target-rpe", value(metadata, "target_rpe")),
        scalar_fragment("target-rir", value(metadata, "target_rir")),
        duration_fragment("rest-after", value(metadata, "rest_after_seconds")),
        scalar_fragment("side", value(metadata, "side"))
      ]
      |> Enum.reject(&is_nil/1)

    annotation =
      cond do
        value(metadata, "deload") == true -> " [deload]"
        not blank?(value(set, :note)) -> " [#{value(set, :note)}]"
        true -> ""
      end

    "- " <> amount <> (load || "") <> format_fragments(extras) <> annotation
  end

  defp prescription_dimension_line(item) do
    case to_string(value(item, :prescription_unit, "")) do
      "reps" -> scalar_line("reps", value(item, :prescription_value))
      "secs" -> duration_line("duration", value(item, :prescription_value))
      "kcal" -> scalar_line("calories", value(item, :prescription_value))
      "meters" -> distance_line("distance", value(item, :prescription_value))
      _ -> nil
    end
  end

  defp format_score(section) do
    if value(section, :scoreable, false) do
      score_config = value(section, :score_config, %{})

      [
        scalar_line("score", value(score_config, :type) |> score_dsl()),
        scalar_line("score-unit", value(score_config, :unit)),
        scalar_line("score-label", value(score_config, :label))
      ]
    end
  end

  defp format_notes(container) do
    notes =
      case value(container, :notes, []) do
        [] ->
          case value(container, :note) do
            nil -> []
            note -> [%{type: "note", body: note}]
          end

        typed_notes ->
          typed_notes
      end

    Enum.map(notes, fn note ->
      type = value(note, :type, "note")
      body = value(note, :body, "")
      ["!#{type}:", String.split(body, "\n", trim: false)]
    end)
  end

  defp format_timer_line(field, value) do
    key = Vocabulary.dsl_key_for_timer_field(field)

    case Vocabulary.timer_value_kind(field) do
      :duration -> duration_line(key, value)
      :distance -> distance_line(key, value)
      :integer -> scalar_line(key, value)
      :enum -> scalar_line(key, value |> to_string() |> String.replace("_", "-"))
      :string -> scalar_line(key, value)
    end
  end

  defp group_identity(item) do
    cond do
      id = value(item, :superset_group_id) -> {:superset, id}
      id = value(item, :alternating_group_id) -> {:alternating, id}
      true -> nil
    end
  end

  defp group_type_from_item(item) do
    cond do
      value(item, :superset_group_id) -> "superset"
      value(item, :alternating_group_id) -> "alternating"
      true -> nil
    end
  end

  defp uniform_prescriptions?([]), do: true

  defp uniform_prescriptions?([first | rest]) do
    signature = set_signature(first)
    Enum.all?(rest, &(set_signature(&1) == signature))
  end

  defp set_signature(set) do
    {
      value(set, :prescription_value),
      value(set, :prescription_unit),
      value(set, :load_value),
      value(set, :load_mode),
      value(set, :note),
      value(set, :metadata, %{})
    }
  end

  defp linear_progression?(progression),
    do: is_map(progression) and to_string(value(progression, "mode")) == "linear"

  defp signed_load_step_line(progression, unit) do
    step = value(progression, "step_value")

    if is_nil(step) do
      nil
    else
      sign = if value(progression, "direction") == "decrease", do: "-", else: "+"
      mode = value(progression, "start_mode")
      "load-step: #{sign}#{Values.format_load(step, mode, unit)}"
    end
  end

  defp load_line(_key, nil, _mode, _unit), do: nil

  defp load_line(key, value, mode, unit),
    do: "#{key}: #{Values.format_load(value, mode, unit)}"

  defp scalar_line(_key, nil), do: nil
  defp scalar_line(_key, ""), do: nil
  defp scalar_line(key, value), do: "#{key}: #{format_scalar(value)}"

  defp number_line(_key, nil), do: nil
  defp number_line(key, value), do: "#{key}: #{Values.format_number(value)}"

  defp duration_line(_key, nil), do: nil
  defp duration_line(key, seconds), do: "#{key}: #{Values.format_duration(seconds)}"

  defp distance_line(_key, nil), do: nil
  defp distance_line(key, meters), do: "#{key}: #{Values.format_distance(meters)}"

  defp duration_range_line(_key, nil), do: nil

  defp duration_range_line(key, [minimum, maximum]),
    do: "#{key}: #{Values.format_duration(minimum)} .. #{Values.format_duration(maximum)}"

  defp boolean_line(_key, nil), do: nil
  defp boolean_line(_key, false), do: nil
  defp boolean_line(key, value), do: "#{key}: #{if(value, do: "true", else: "false")}"

  defp list_line(_key, []), do: nil
  defp list_line(_key, nil), do: nil
  defp list_line(key, values), do: "#{key}: #{Enum.map_join(values, ", ", &format_scalar/1)}"

  defp unit_line(_key, nil, _unit), do: nil
  defp unit_line(key, value, unit), do: "#{key}: #{Values.format_number(value)} #{unit}"

  defp bpm_line(_key, nil), do: nil
  defp bpm_line(key, value), do: "#{key}: #{value} bpm"

  defp scalar_fragment(_key, nil), do: nil
  defp scalar_fragment(key, value), do: "#{key}: #{value}"

  defp duration_fragment(_key, nil), do: nil
  defp duration_fragment(key, value), do: "#{key}: #{Values.format_duration(value)}"

  defp format_fragments([]), do: ""
  defp format_fragments(fragments), do: "; " <> Enum.join(fragments, "; ")

  defp format_interval(1), do: "odd"
  defp format_interval(2), do: "even"
  defp format_interval(value), do: value

  defp format_scalar(value) when is_atom(value), do: value |> Atom.to_string() |> format_scalar()

  defp format_scalar(value) when is_binary(value) do
    if value != String.trim(value) or
         String.contains?(value, ["\"", "\n", "\r", "[", "]"]) do
      escaped =
        value
        |> String.replace("\\", "\\\\")
        |> String.replace("\"", "\\\"")
        |> String.replace("\n", "\\n")

      "\"#{escaped}\""
    else
      value
    end
  end

  defp format_scalar(value), do: to_string(value)

  defp metadata_value(item, key),
    do: item |> value(:prescription_metadata, %{}) |> value(key)

  defp display_load(item) do
    case value(item, :load_value) do
      nil ->
        case value(item, :set_prescriptions, []) do
          [first | _] ->
            {
              value(first, :load_value),
              value(first, :load_mode),
              first |> value(:metadata, %{}) |> value("load_unit")
            }

          [] ->
            {nil, nil, nil}
        end

      load_value ->
        {load_value, value(item, :load_mode), metadata_value(item, "load_unit")}
    end
  end

  defp score_dsl(nil), do: nil
  defp score_dsl("rounds+reps"), do: "rounds-and-reps"
  defp score_dsl(value), do: dsl_enum(value)

  defp dsl_enum(nil), do: nil
  defp dsl_enum(value), do: value |> to_string() |> String.replace("_", "-")

  defp flatten_lines(lines) do
    lines
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce([], fn line, acc ->
      if acc == [] or line == "" or List.last(acc) == "" do
        acc ++ [line]
      else
        acc ++ [line]
      end
    end)
  end

  defp value(map, key, default \\ nil)
  defp value(nil, _key, default), do: default

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
