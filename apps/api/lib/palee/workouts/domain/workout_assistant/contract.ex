defmodule Palee.Workouts.Domain.WorkoutAssistant.Contract do
  @moduledoc """
  Strict contract for the parser agent's raw answer.

  `FreeTextAnalysis.normalize/2` is forgiving (it drops what it cannot use);
  this module is strict and explains *why* an answer is not acceptable, in
  terms the model can act on. Violations feed the repair loop and the agents'
  `validate_draft` tool. Paths use the agent's own field names.

  The workout and every section are validated against the canonical JSON
  Schemas of `FormatSchema` (one per section format), so the agent, its
  `get_section_schema` tool and this check share one definition.
  """

  alias Palee.Workouts.Domain.JsonSchema
  alias Palee.Workouts.Domain.WorkoutAssistant.FormatSchema
  alias Palee.Workouts.Domain.WorkoutDsl.Vocabulary

  @workout_keys ~w(title type subtitle description difficulty estimated_duration_minutes equipment tags)
  @section_keys ~w(name format timer note exercises)
  @exercise_keys ~w(name sets reps duration_seconds calories distance_meters load_kg load_percent_1rm bodyweight rest_seconds tempo note)
  @prescription_keys ~w(reps duration_seconds calories distance_meters)
  @load_keys ~w(load_kg load_percent_1rm bodyweight)
  @issue_keys ~w(path severity message suggestion_label suggested_value find_text replace_text source_text)
  @missing_keys ~w(path reason suggested_value insert_text)
  @assumption_keys ~w(path message source_text)
  @max_violations 40

  @doc "Returns a list of `%{\"path\" => ..., \"problem\" => ...}` (empty when valid)."
  def check(raw, source) when is_map(raw) and is_binary(source) do
    (top_level(raw) ++
       workout(Map.get(raw, "workout")) ++
       sections(Map.get(raw, "sections")) ++
       issues(Map.get(raw, "issues"), raw, source) ++
       missing_fields(Map.get(raw, "missing_fields")) ++
       assumptions(Map.get(raw, "assumptions"), raw))
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

    assumptions =
      case Map.get(raw, "assumptions") do
        nil -> []
        list when is_list(list) -> []
        _other -> [violation("assumptions", "must be an array (use [] when empty)")]
      end

    missing ++ assumptions ++ unknown_keys(raw, ["assumptions" | Map.keys(expected)], "")
  end

  defp kind("workout"), do: "an object"
  defp kind(_key), do: "an array (use [] when empty)"

  ## Workout

  defp workout(%{} = workout),
    do: JsonSchema.validate_at(FormatSchema.workout_schema(), workout, "workout")

  defp workout(_workout), do: []

  ## Sections
  #
  # Every section is validated against the canonical JSON Schema of its own
  # format (`FormatSchema`), then against the cross-field rules of that format.

  defp sections(sections) when is_list(sections) do
    sections
    |> Enum.with_index()
    |> Enum.flat_map(fn {section, index} -> section(section, "sections.#{index}") end)
  end

  defp sections(_sections), do: []

  defp section(%{} = section, path) do
    {section, entry_violations} = prepare_timer(section, path)

    case Map.get(section, "format") do
      nil ->
        entry_violations ++
          [
            violation(
              "#{path}.format",
              "is required: infer the block's format (use \"untimed\" for a block without a clock)"
            )
          ]

      format ->
        case FormatSchema.canonical(format) do
          nil ->
            entry_violations ++
              [
                violation(
                  "#{path}.format",
                  "#{inspect(format)} is not a known format; use one of #{Enum.join(Vocabulary.section_formats(), ", ")}"
                )
              ]

          canonical ->
            section = Map.put(section, "format", canonical)

            shape =
              canonical
              |> FormatSchema.section_schema()
              |> JsonSchema.validate_at(section, path)
              |> Enum.map(&explain(&1, canonical, path))

            rules = if shape == [], do: FormatSchema.rule_violations(section, path), else: []
            entry_violations ++ shape ++ exercises(Map.get(section, "exercises"), path) ++ rules
        end
    end
  end

  defp section(_section, path), do: [violation(path, "must be an object")]

  # The timer may come as an object (canonical) or as the older list of
  # {key, value} entries; numeric strings in the list form are accepted.
  defp prepare_timer(section, path) do
    case Map.get(section, "timer") do
      entries when is_list(entries) ->
        {timer, violations} =
          entries
          |> Enum.with_index()
          |> Enum.reduce({%{}, []}, fn {entry, index}, {timer, violations} ->
            case entry do
              %{"key" => key} when is_binary(key) ->
                key = key |> String.trim() |> String.replace("-", "_")
                {Map.put(timer, key, numeric(Map.get(entry, "value"))), violations}

              _other ->
                {timer,
                 [
                   violation("#{path}.timer.#{index}", "must be {\"key\": ..., \"value\": ...}")
                   | violations
                 ]}
            end
          end)

        section =
          if timer == %{},
            do: Map.delete(section, "timer"),
            else: Map.put(section, "timer", timer)

        {section, Enum.reverse(violations)}

      _other ->
        {section, []}
    end
  end

  defp numeric(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number
      _other -> value
    end
  end

  defp numeric(value), do: value

  defp explain(%{"path" => violation_path, "problem" => "is required"} = violation, format, path) do
    if violation_path == "#{path}.timer" or String.starts_with?(violation_path, "#{path}.timer.") do
      %{
        violation
        | "problem" =>
            "is required for #{format} (needs #{Enum.join(FormatSchema.required_timer_keys(format), ", ")}). If the text does not say it, use format \"untimed\" and report an issue instead of inventing values"
      }
    else
      violation
    end
  end

  defp explain(%{"problem" => "is not allowed here"} = violation, format, _path),
    do: %{violation | "problem" => "is not part of the #{format} schema; remove it"}

  defp explain(violation, _format, _path), do: violation

  ## Exercises (rules JSON Schema cannot express)

  defp exercises(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%{} = exercise, index} -> exercise(exercise, "#{path}.exercises.#{index}")
      _other -> []
    end)
  end

  defp exercises(_list, _path), do: []

  defp exercise(exercise, path) do
    only_one(
      exercise,
      @prescription_keys,
      path,
      "prescription (reps, duration_seconds, calories or distance_meters)"
    ) ++
      only_one(exercise, @load_keys, path, "load (load_kg, load_percent_1rm or bodyweight)")
  end

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

  ## Assumptions
  #
  # Values the agent inferred rather than read (a convention such as Tabata
  # 20/10 × 8, a computed duration, an expanded abbreviation). They are shown
  # to the coach to keep or reject, so each must point at a real field.

  defp assumptions(list, raw) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      path = "assumptions.#{index}"

      case entry do
        %{} ->
          unknown_keys(entry, @assumption_keys, path) ++
            required_string(entry, "message", path) ++
            assumption_path(Map.get(entry, "path"), raw, path)

        _other ->
          [violation(path, "must be an object")]
      end
    end)
  end

  defp assumptions(_list, _raw), do: []

  defp assumption_path(target, raw, path) when is_binary(target) do
    if resolves?(raw, target) or timer_key?(raw, target),
      do: [],
      else: [
        violation(
          "#{path}.path",
          "\"#{target}\" does not point at a field of your workout, sections or section timers"
        )
      ]
  end

  defp assumption_path(_target, _raw, path), do: [violation("#{path}.path", "is required")]

  defp timer_key?(raw, target) do
    case String.split(target, ".", trim: true) do
      ["sections", index, "timer", key] ->
        timer = at(raw, ["sections", index, "timer"])
        is_map(timer) and Map.has_key?(timer, key)

      _other ->
        false
    end
  end

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

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(false), do: false
  defp present?(_value), do: true

  defp join("", key), do: key
  defp join(path, key), do: "#{path}.#{key}"

  defp violation(path, problem), do: %{"path" => path, "problem" => problem}
end
