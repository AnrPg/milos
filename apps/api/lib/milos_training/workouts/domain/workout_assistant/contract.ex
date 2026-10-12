defmodule MilosTraining.Workouts.Domain.WorkoutAssistant.Contract do
  @moduledoc """
  Strict contract for the parser agent's raw answer.

  `FreeTextAnalysis.normalize/2` is forgiving (it drops what it cannot use);
  this module is strict and explains *why* an answer is not acceptable, in
  terms the model can act on. Violations feed the repair loop and the agents'
  `validate_draft` tool. Paths use the agent's own field names.
  """

  alias MilosTraining.Workouts.Domain.FreeTextAnalysis
  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  @workout_keys ~w(title type subtitle description difficulty estimated_duration_minutes equipment tags)
  @section_keys ~w(name format timer note exercises)
  @exercise_keys ~w(name sets reps duration_seconds calories distance_meters load_kg load_percent_1rm bodyweight rest_seconds tempo note)
  @prescription_keys ~w(reps duration_seconds calories distance_meters)
  @load_keys ~w(load_kg load_percent_1rm bodyweight)
  @issue_keys ~w(path severity message suggestion_label suggested_value find_text replace_text)
  @missing_keys ~w(path reason suggested_value insert_text)
  @max_violations 40

  @doc "Returns a list of `%{\"path\" => ..., \"problem\" => ...}` (empty when valid)."
  def check(raw, source) when is_map(raw) and is_binary(source) do
    (top_level(raw) ++
       workout(Map.get(raw, "workout")) ++
       sections(Map.get(raw, "sections")) ++
       issues(Map.get(raw, "issues"), raw, source) ++
       missing_fields(Map.get(raw, "missing_fields")))
    |> Enum.take(@max_violations)
  end

  def check(_raw, _source), do: [violation("", "the answer must be one JSON object")]

  ## Top level

  defp top_level(raw) do
    expected = %{
      "workout" => &is_map/1,
      "sections" => &is_list/1,
      "issues" => &is_list/1,
      "missing_fields" => &is_list/1
    }

    missing =
      Enum.flat_map(expected, fn {key, ok?} ->
        if ok?.(Map.get(raw, key)),
          do: [],
          else: [violation(key, "is required and must be #{kind(key)}")]
      end)

    missing ++ unknown_keys(raw, Map.keys(expected), "")
  end

  defp kind("workout"), do: "an object"
  defp kind(_key), do: "an array (use [] when empty)"

  ## Workout

  defp workout(%{} = workout) do
    unknown_keys(workout, @workout_keys, "workout") ++
      enum_check(workout, "type", FreeTextAnalysis.workout_types(), "workout.type") ++
      enum_check(workout, "difficulty", FreeTextAnalysis.difficulties(), "workout.difficulty") ++
      positive_number(workout, "estimated_duration_minutes", "workout") ++
      string_list(workout, "equipment", "workout") ++
      string_list(workout, "tags", "workout") ++
      title(Map.get(workout, "title"))
  end

  defp workout(_workout), do: []

  defp title(nil), do: []

  defp title(title) when is_binary(title) do
    length = String.length(String.trim(title))

    if length >= 3 and length <= 160,
      do: [],
      else: [
        violation(
          "workout.title",
          "must be 3 to 160 characters, or omitted if the text has no title"
        )
      ]
  end

  defp title(_title), do: [violation("workout.title", "must be a string")]

  ## Sections

  defp sections(sections) when is_list(sections) do
    sections
    |> Enum.with_index()
    |> Enum.flat_map(fn {section, index} -> section(section, "sections.#{index}") end)
  end

  defp sections(_sections), do: []

  defp section(%{} = section, path) do
    unknown_keys(section, @section_keys, path) ++
      required_string(section, "name", path) ++
      format(section, path) ++
      exercises(Map.get(section, "exercises"), path)
  end

  defp section(_section, path), do: [violation(path, "must be an object")]

  defp format(section, path) do
    case Map.get(section, "format") do
      nil ->
        timer_without_format(section, path)

      format when is_binary(format) ->
        case Vocabulary.resolve_format(format) do
          {:ok, canonical, _composition} ->
            timer(Map.get(section, "timer"), canonical, path)

          {:error, _reason} ->
            [
              violation(
                "#{path}.format",
                "\"#{format}\" is not a known format; use one of #{Enum.join(Vocabulary.section_formats(), ", ")}"
              )
            ]
        end

      _other ->
        [violation("#{path}.format", "must be a string")]
    end
  end

  defp timer_without_format(section, path) do
    case Map.get(section, "timer") do
      list when is_list(list) and list != [] ->
        [violation("#{path}.format", "is required when timer keys are given")]

      _other ->
        []
    end
  end

  defp timer(nil, canonical, path), do: required_timer_keys(%{}, canonical, path)

  defp timer(entries, canonical, path) when is_list(entries) do
    allowed = canonical |> Vocabulary.allowed_timer_fields() |> Enum.map(&Atom.to_string/1)

    {values, violations} =
      entries
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {entry, index}, {values, violations} ->
        entry_path = "#{path}.timer.#{index}"
        key = entry_key(entry)
        value = if is_map(entry), do: Map.get(entry, "value")

        cond do
          is_nil(key) ->
            {values,
             [violation(entry_path, "must be {\"key\": ..., \"value\": ...}") | violations]}

          key not in allowed ->
            {values,
             [
               violation(
                 entry_path,
                 "key \"#{key}\" is not valid for #{canonical}; allowed: #{Enum.join(allowed, ", ")}"
               )
               | violations
             ]}

          not timer_value_ok?(key, value) ->
            {values,
             [
               violation(entry_path, "value for \"#{key}\" must be #{timer_value_hint(key)}")
               | violations
             ]}

          true ->
            {Map.put(values, key, value), violations}
        end
      end)

    Enum.reverse(violations) ++ required_timer_keys(values, canonical, path)
  end

  defp timer(_entries, _canonical, path),
    do: [violation("#{path}.timer", "must be an array of {key, value}")]

  defp required_timer_keys(values, canonical, path) do
    missing =
      canonical
      |> Vocabulary.required_timer_fields()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.reject(&Map.has_key?(values, &1))

    case missing do
      [] ->
        []

      keys ->
        [
          violation(
            "#{path}.timer",
            "#{canonical} needs #{Enum.join(keys, ", ")}. If the text does not say it, use format \"untimed\" and report an issue instead of inventing values"
          )
        ]
    end
  end

  defp entry_key(%{"key" => key}) when is_binary(key),
    do: String.replace(String.trim(key), "-", "_")

  defp entry_key(_entry), do: nil

  defp timer_value_ok?(key, value) do
    case Vocabulary.timer_value_kind(String.to_existing_atom(key)) do
      :enum -> to_string(value) in Vocabulary.timer_enum_values(String.to_existing_atom(key))
      :string -> is_binary(value) or is_number(value)
      _numeric -> positive_integer_like?(value)
    end
  rescue
    ArgumentError -> false
  end

  defp timer_value_hint(key) do
    case Vocabulary.timer_value_kind(String.to_existing_atom(key)) do
      :enum ->
        "one of #{Enum.join(Vocabulary.timer_enum_values(String.to_existing_atom(key)), ", ")}"

      :string ->
        "text"

      :duration ->
        "a whole number of seconds"

      _numeric ->
        "a whole positive number"
    end
  rescue
    ArgumentError -> "valid"
  end

  ## Exercises

  defp exercises(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {exercise, index} -> exercise(exercise, "#{path}.exercises.#{index}") end)
  end

  defp exercises(nil, path),
    do: [violation("#{path}.exercises", "is required (use [] for a block without exercises)")]

  defp exercises(_list, path), do: [violation("#{path}.exercises", "must be an array")]

  defp exercise(%{} = exercise, path) do
    unknown_keys(exercise, @exercise_keys, path) ++
      required_string(exercise, "name", path) ++
      only_one(
        exercise,
        @prescription_keys,
        path,
        "prescription (reps, duration_seconds, calories or distance_meters)"
      ) ++
      only_one(exercise, @load_keys, path, "load (load_kg, load_percent_1rm or bodyweight)") ++
      Enum.flat_map(
        ~w(sets reps duration_seconds calories distance_meters),
        &positive_number(exercise, &1, path)
      ) ++
      Enum.flat_map(
        ~w(load_kg load_percent_1rm rest_seconds),
        &non_negative_number(exercise, &1, path)
      ) ++
      percent(exercise, path) ++
      bodyweight(exercise, path)
  end

  defp exercise(_exercise, path), do: [violation(path, "must be an object")]

  defp only_one(map, keys, path, label) do
    present = Enum.filter(keys, &present?(Map.get(map, &1)))

    if length(present) > 1,
      do: [
        violation(
          path,
          "has more than one #{label}: #{Enum.join(present, ", ")}; keep the one the text states"
        )
      ],
      else: []
  end

  defp percent(map, path) do
    case Map.get(map, "load_percent_1rm") do
      nil -> []
      value when is_number(value) and value > 0 and value <= 150 -> []
      _other -> [violation("#{path}.load_percent_1rm", "must be a percentage between 1 and 150")]
    end
  end

  defp bodyweight(map, path) do
    case Map.get(map, "bodyweight") do
      nil -> []
      value when is_boolean(value) -> []
      _other -> [violation("#{path}.bodyweight", "must be true or omitted")]
    end
  end

  ## Issues and missing fields

  defp issues(list, raw, source) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {issue, index} -> issue(issue, raw, source, "issues.#{index}") end)
  end

  defp issues(_list, _raw, _source), do: []

  defp issue(%{} = issue, raw, source, path) do
    unknown_keys(issue, @issue_keys, path) ++
      required_string(issue, "message", path) ++
      issue_path(Map.get(issue, "path"), raw, path) ++
      enum_check(issue, "severity", ~w(error warning), "#{path}.severity") ++
      text_edit(issue, source, path) ++
      consistent_fix(issue, raw, path) ++
      actionable(issue, path)
  end

  defp issue(_issue, _raw, _source, path), do: [violation(path, "must be an object")]

  defp issue_path(target, raw, path) when is_binary(target) do
    if resolves?(raw, target),
      do: [],
      else: [
        violation(
          "#{path}.path",
          "\"#{target}\" does not point at a field of your workout or sections"
        )
      ]
  end

  defp issue_path(_target, _raw, path), do: [violation("#{path}.path", "is required")]

  defp text_edit(issue, source, path) do
    find = Map.get(issue, "find_text")
    replace = Map.get(issue, "replace_text")

    cond do
      is_nil(find) and is_nil(replace) ->
        []

      not is_binary(find) or not is_binary(replace) ->
        [violation(path, "find_text and replace_text must both be strings")]

      not String.contains?(source, find) ->
        [
          violation(
            "#{path}.find_text",
            "\"#{find}\" is not an exact substring of the coach's text; copy it character for character"
          )
        ]

      find == replace ->
        [violation("#{path}.replace_text", "must differ from find_text")]

      true ->
        []
    end
  end

  # When the text fix replaces the field's whole value, the field fix must be
  # the same words, or Accept would leave text and data disagreeing.
  defp consistent_fix(issue, raw, path) do
    find = Map.get(issue, "find_text")
    replace = Map.get(issue, "replace_text")
    value = Map.get(issue, "suggested_value")
    current = current_value(raw, Map.get(issue, "path"))

    if is_binary(current) and current == find and is_binary(value) and is_binary(replace) and
         value != replace,
       do: [
         violation(
           "#{path}.suggested_value",
           "must equal replace_text (\"#{replace}\") because find_text is the field's whole value"
         )
       ],
       else: []
  end

  defp current_value(raw, target) when is_binary(target) do
    segments = target |> String.replace(~r/\[(\d+)\]/, ".\\1") |> String.split(".", trim: true)

    case segments do
      ["workout", field] -> at(raw, ["workout", field])
      [field] -> at(raw, ["workout", field])
      other -> at(raw, other)
    end
  end

  defp current_value(_raw, _target), do: nil

  defp actionable(issue, path) do
    has_fix = present?(Map.get(issue, "suggested_value")) or present?(Map.get(issue, "find_text"))

    if has_fix or Map.get(issue, "severity") == "error",
      do: [],
      else: [violation(path, "a warning needs suggested_value and/or find_text + replace_text")]
  end

  defp missing_fields(list) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      path = "missing_fields.#{index}"

      case entry do
        %{} ->
          unknown_keys(entry, @missing_keys, path) ++
            required_string(entry, "path", path) ++
            required_string(entry, "suggested_value", path)

        _other ->
          [violation(path, "must be an object")]
      end
    end)
  end

  defp missing_fields(_list), do: []

  ## Helpers

  # A path resolves when its parent container exists in the raw answer and
  # the last segment is a known field for that container.
  defp resolves?(raw, target) do
    segments = target |> String.replace(~r/\[(\d+)\]/, ".\\1") |> String.split(".", trim: true)

    case segments do
      ["workout", field] ->
        field in @workout_keys

      [field] ->
        field in @workout_keys

      ["sections", index, field] ->
        field in @section_keys and at(raw, ["sections", index]) != nil

      ["sections", index, "exercises", exercise, field] ->
        field in @exercise_keys and at(raw, ["sections", index, "exercises", exercise]) != nil

      _other ->
        false
    end
  end

  defp at(value, []), do: value
  defp at(%{} = map, [key | rest]), do: at(Map.get(map, key), rest)

  defp at(list, [index | rest]) when is_list(list) do
    case Integer.parse(index) do
      {position, ""} -> at(Enum.at(list, position), rest)
      _other -> nil
    end
  end

  defp at(_value, _segments), do: nil

  defp unknown_keys(map, allowed, path) do
    map
    |> Map.keys()
    |> Enum.reject(&(&1 in allowed))
    |> Enum.map(&violation(join(path, &1), "is not part of the schema; remove it"))
  end

  defp required_string(map, key, path) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: [violation(join(path, key), "must not be empty")],
          else: []

      _other ->
        [violation(join(path, key), "is required and must be a string")]
    end
  end

  defp enum_check(map, key, values, path) do
    case Map.get(map, key) do
      nil ->
        []

      value ->
        if value in values,
          do: [],
          else: [violation(path, "must be one of #{Enum.join(values, ", ")}")]
    end
  end

  defp positive_number(map, key, path) do
    case Map.get(map, key) do
      nil -> []
      value when is_number(value) and value > 0 -> []
      _other -> [violation(join(path, key), "must be a positive number")]
    end
  end

  defp non_negative_number(map, key, path) do
    case Map.get(map, key) do
      nil -> []
      value when is_number(value) and value >= 0 -> []
      _other -> [violation(join(path, key), "must be a number ≥ 0")]
    end
  end

  defp string_list(map, key, path) do
    case Map.get(map, key) do
      nil ->
        []

      list when is_list(list) ->
        if Enum.all?(list, &is_binary/1),
          do: [],
          else: [violation(join(path, key), "must contain only strings")]

      _other ->
        [violation(join(path, key), "must be an array of strings")]
    end
  end

  defp positive_integer_like?(value) when is_integer(value), do: value > 0

  defp positive_integer_like?(value) when is_float(value),
    do: value > 0 and value == Float.round(value)

  defp positive_integer_like?(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number > 0
      _other -> false
    end
  end

  defp positive_integer_like?(_value), do: false

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(false), do: false
  defp present?(_value), do: true

  defp join("", key), do: key
  defp join(path, key), do: "#{path}.#{key}"

  defp violation(path, problem), do: %{"path" => path, "problem" => problem}
end
