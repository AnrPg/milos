defmodule Palee.Workouts.Domain.FreeTextAnalysis do
  @moduledoc """
  Pure normalization of an assistant's reading of a free-text workout.

  The assistant (an LLM behind the `WorkoutTextAnalyzer` port) returns an
  untrusted, loosely typed interpretation of the coach's text. This module
  turns it into the canonical workout shape accepted by publication
  (`title`, `type`, workout metadata, `sections` with `timer_config` and
  `exercises`) and never trusts a value it cannot validate:

    * values that do not fit the canonical schema are dropped and reported as
      issues, so the coach can accept a corrected value or reject the field;
    * assistant issues and suggestions are only kept when they point at a
      known canonical field;
    * text edits are only kept when the text they replace exists verbatim in
      the source, so accepting one can never corrupt unrelated text;
    * required fields (`title`, `type`, section and exercise names) are
      flagged so the caller can block creation when they are rejected.

  Paths use dot notation with numeric list indexes, for example
  `sections.0.exercises.2.load_value`.
  """

  alias Palee.Workouts.Domain.{TimerConfig, WorkoutType}
  alias Palee.Workouts.Domain.WorkoutAssistant.Proofreading
  alias Palee.Workouts.Domain.WorkoutDsl.Vocabulary

  @difficulties ~w(beginner intermediate advanced all-levels)
  @prescription_units ~w(reps secs kcal meters)
  @load_modes ~w(absolute pct_1rm bw)
  @severities ~w(error warning info)
  @max_sections 30
  @max_exercises 60
  @max_issues 40
  @max_suggestions 30
  @max_assumptions 20
  @max_list_items 20

  @workout_fields ~w(title type subtitle description difficulty estimated_duration_seconds equipment tags)
  @section_fields ~w(name note timer_config)
  @exercise_fields ~w(name sets interval_assignment prescription_value prescription_unit load_value load_mode rest_seconds tempo note)

  # Workout-level optional fields worth proposing even when the assistant had
  # no value: the coach can type one in from the suggestion card.
  @recommended_workout_fields ~w(difficulty estimated_duration_seconds equipment description)

  @doc "Canonical fields that must hold a value for a workout to be created."
  def required_path?(path) when is_binary(path) do
    path in ["title", "type"] or
      Regex.match?(~r/^sections\.\d+\.name$/, path) or
      Regex.match?(~r/^sections\.\d+\.exercises\.\d+\.name$/, path)
  end

  def required_path?(_path), do: false

  def workout_types, do: Enum.map(WorkoutType.values(), &Atom.to_string/1)
  def difficulties, do: @difficulties
  def prescription_units, do: @prescription_units
  def load_modes, do: @load_modes
  def section_formats, do: Vocabulary.section_formats()

  @doc """
  Normalizes raw assistant output against `source` (the coach's plain text).

  Returns `%{workout: map, issues: list, suggestions: list, summary: map}`.
  """
  def normalize(raw, source, corrections \\ [])

  def normalize(raw, source, corrections) when is_map(raw) and is_binary(source) do
    raw_workout = map_value(raw, "workout")
    raw_sections = raw |> list_value("sections") |> Enum.take(@max_sections)

    {workout, workout_issues} = normalize_workout(raw_workout)
    {sections, section_issues} = normalize_sections(raw_sections)
    workout = Map.put(workout, "sections", sections)

    assistant_issues =
      raw
      |> list_value("issues")
      |> Enum.flat_map(&normalize_assistant_issue(&1, workout, source))

    covered_edits =
      assistant_issues
      |> Enum.map(&get_in(&1, ["suggestion", "text_edit", "find"]))
      |> Enum.filter(&is_binary/1)

    # The parser already proposed a fix for the same words: keep one CTA.
    correction_issues =
      corrections
      |> Proofreading.to_issues(workout)
      |> Enum.reject(&overlaps?(get_in(&1, ["suggestion", "text_edit", "find"]), covered_edits))

    # Inferred values come last: a real problem on the same field wins.
    assumption_issues =
      raw
      |> list_value("assumptions")
      |> Enum.take(@max_assumptions)
      |> Enum.flat_map(&normalize_assumption(&1, workout))
      |> merge_assumptions()

    issues =
      (workout_issues ++
         section_issues ++ assistant_issues ++ correction_issues ++ assumption_issues)
      |> dedupe_issues()
      |> Enum.take(@max_issues)
      |> Enum.with_index(1)
      |> Enum.map(fn {issue, index} -> Map.put(issue, "id", "issue-#{index}") end)

    issue_paths = MapSet.new(issues, & &1["path"])

    suggestions =
      raw
      |> list_value("missing_fields")
      |> Enum.flat_map(&normalize_assistant_suggestion(&1, workout, source))
      |> Kernel.++(recommended_suggestions(workout))
      |> Enum.reject(&MapSet.member?(issue_paths, &1["path"]))
      |> dedupe_by_path()
      |> Enum.take(@max_suggestions)
      |> Enum.with_index(1)
      |> Enum.map(fn {suggestion, index} -> Map.put(suggestion, "id", "suggestion-#{index}") end)

    %{
      "workout" => workout,
      "issues" => issues,
      "suggestions" => suggestions,
      "summary" => summary(workout, issues)
    }
  end

  def normalize(_raw, source, corrections) when is_binary(source),
    do: normalize(%{}, source, corrections)

  @doc "Coerces a raw value for a canonical path. Returns `{:ok, value}` or `:error`."
  def coerce(path, value) when is_binary(path) do
    case field_spec(path) do
      nil -> :error
      spec -> coerce_value(spec, value)
    end
  end

  ## Workout

  defp normalize_workout(raw) do
    {title, title_issues} = required_string("title", map_value_raw(raw, "title"), 3, 160)

    {type, type_issues} =
      case coerce("type", map_value_raw(raw, "type")) do
        {:ok, value} -> {value, []}
        :error -> {nil, [required_issue("type", "missing_type", map_value_raw(raw, "type"))]}
      end

    duration =
      case map_value_raw(raw, "estimated_duration_minutes") do
        nil ->
          map_value_raw(raw, "estimated_duration_seconds")

        minutes when is_number(minutes) ->
          round(minutes * 60)

        minutes ->
          with {:ok, number} <- parse_number(minutes),
               do: round(number * 60),
               else: (_ -> minutes)
      end

    optional = [
      {"subtitle", map_value_raw(raw, "subtitle")},
      {"description", map_value_raw(raw, "description")},
      {"difficulty", map_value_raw(raw, "difficulty")},
      {"estimated_duration_seconds", duration},
      {"equipment", map_value_raw(raw, "equipment")},
      {"tags", map_value_raw(raw, "tags")}
    ]

    {workout, optional_issues} =
      Enum.reduce(optional, {%{"title" => title, "type" => type}, []}, fn {field, value},
                                                                          {acc, issues} ->
        case optional_value(field, value) do
          {:ok, normalized} ->
            {Map.put(acc, field, normalized), issues}

          {:invalid, original} ->
            {Map.put(acc, field, nil), [invalid_issue(field, original) | issues]}
        end
      end)

    {workout, title_issues ++ type_issues ++ Enum.reverse(optional_issues)}
  end

  ## Sections

  defp normalize_sections(raw_sections) do
    raw_sections
    |> Enum.with_index()
    |> Enum.map_reduce([], fn {raw, index}, issues ->
      {section, section_issues} = normalize_section(raw, index)
      {section, issues ++ section_issues}
    end)
  end

  defp normalize_section(raw, index) when is_map(raw) do
    prefix = "sections.#{index}"

    {name, name_issues} =
      case blank_to_nil(map_value_raw(raw, "name")) do
        nil ->
          {"Section #{index + 1}",
           [required_issue("#{prefix}.name", "missing_section_name", nil)]}

        name ->
          required_string("#{prefix}.name", name, 1, 160)
      end

    {timer_config, timer_issues} = normalize_timer(raw, prefix)

    {note, note_issues} =
      case optional_value("#{prefix}.note", map_value_raw(raw, "note")) do
        {:ok, value} -> {value, []}
        {:invalid, original} -> {nil, [invalid_issue("#{prefix}.note", original)]}
      end

    {exercises, exercise_issues} =
      raw
      |> list_value("exercises")
      |> Enum.take(@max_exercises)
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {exercise, exercise_index}, acc ->
        {normalized, issues} =
          normalize_exercise(exercise, "#{prefix}.exercises.#{exercise_index}")

        {normalized, acc ++ issues}
      end)

    section =
      %{"name" => name, "note" => note, "timer_config" => timer_config, "exercises" => exercises}
      |> Map.merge(normalize_score(raw, timer_config))

    {section, name_issues ++ timer_issues ++ note_issues ++ exercise_issues}
  end

  defp normalize_section(_raw, index) do
    prefix = "sections.#{index}"

    {%{"name" => "Section #{index + 1}", "note" => nil, "timer_config" => nil, "exercises" => []},
     [required_issue("#{prefix}.name", "missing_section_name", nil)]}
  end

  defp normalize_timer(raw, prefix) do
    path = "#{prefix}.timer_config"
    format = blank_to_nil(map_value_raw(raw, "format"))

    case format && Vocabulary.resolve_format(format) do
      nil ->
        {nil, []}

      {:ok, canonical, _composition} ->
        fields = timer_fields(raw, canonical)

        case TimerConfig.normalize(Map.put(fields, "type", canonical)) do
          {:ok, config} ->
            {stringify_keys(config), []}

          {:error, _reason} ->
            {nil,
             [
               issue(path, "invalid_timer", "warning", %{
                 "format" => canonical,
                 "missing" =>
                   Enum.map(Vocabulary.required_timer_fields(canonical), &Atom.to_string/1) --
                     Map.keys(fields)
               })
             ]}
        end

      {:error, :unknown_format} ->
        {nil, [issue(path, "unknown_format", "warning", %{"value" => format})]}
    end
  end

  defp timer_fields(raw, format) do
    allowed = format |> Vocabulary.allowed_timer_fields() |> Map.new(&{Atom.to_string(&1), &1})

    raw
    |> timer_entries()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key = to_key(key)

      with field when not is_nil(field) <- Map.get(allowed, key),
           {:ok, value} <- coerce_timer_value(field, value) do
        Map.put(acc, key, value)
      else
        _ -> acc
      end
    end)
  end

  # Canonical shape is an object (`{"duration_seconds": 720}`); the older list
  # of `{key, value}` entries is still accepted.
  defp timer_entries(raw) do
    case map_value_raw(raw, "timer") do
      %{} = timer ->
        Enum.to_list(timer)

      entries when is_list(entries) ->
        Enum.map(entries, &{map_value_raw(&1, "key"), map_value_raw(&1, "value")})

      _other ->
        []
    end
  end

  # A score the format allows marks the section scoreable (ADR-110).
  defp normalize_score(raw, timer_config) do
    format = timer_config && Map.get(timer_config, "type")
    score = raw |> map_value_raw("score") |> to_key()

    if format && score && score in Vocabulary.allowed_score_types(format),
      do: %{"scoreable" => true, "score_config" => %{"type" => score}},
      else: %{}
  end

  defp coerce_timer_value(field, value) do
    case Vocabulary.timer_value_kind(field) do
      kind when kind in [:duration, :distance, :integer] ->
        coerce_value({:integer, 0}, value)

      :enum ->
        string = value |> to_string() |> String.trim() |> String.downcase()

        if string in Vocabulary.timer_enum_values(field), do: {:ok, string}, else: :error

      :string ->
        coerce_value({:string, 120}, value)
    end
  end

  ## Exercises

  defp normalize_exercise(raw, prefix) when is_map(raw) do
    {name, name_issues} =
      case blank_to_nil(map_value_raw(raw, "name")) do
        nil -> {nil, [required_issue("#{prefix}.name", "missing_exercise_name", nil)]}
        name -> required_string("#{prefix}.name", name, 1, 160)
      end

    {prescription, prescription_issues} = prescription(raw, prefix)
    {load, load_issues} = load(raw, prefix)

    {optional, optional_issues} =
      [
        {"sets", map_value_raw(raw, "sets")},
        {"interval_assignment", map_value_raw(raw, "interval_assignment")},
        {"rest_seconds", map_value_raw(raw, "rest_seconds")},
        {"tempo", map_value_raw(raw, "tempo")},
        {"note", map_value_raw(raw, "note")}
      ]
      |> Enum.reduce({%{}, []}, fn {field, value}, {acc, issues} ->
        path = "#{prefix}.#{field}"

        case optional_value(path, value) do
          {:ok, normalized} ->
            {Map.put(acc, field, normalized), issues}

          {:invalid, original} ->
            {Map.put(acc, field, nil), [invalid_issue(path, original) | issues]}
        end
      end)

    exercise =
      %{"name" => name, "item_type" => "exercise"}
      |> Map.merge(prescription)
      |> Map.merge(load)
      |> Map.merge(optional)

    {exercise, name_issues ++ prescription_issues ++ load_issues ++ Enum.reverse(optional_issues)}
  end

  defp normalize_exercise(_raw, prefix) do
    {%{"name" => nil, "item_type" => "exercise"},
     [required_issue("#{prefix}.name", "missing_exercise_name", nil)]}
  end

  defp prescription(raw, prefix) do
    candidates = [
      {"reps", "reps"},
      {"duration_seconds", "secs"},
      {"calories", "kcal"},
      {"distance_meters", "meters"}
    ]

    present =
      Enum.flat_map(candidates, fn {key, unit} ->
        case map_value_raw(raw, key) do
          nil -> []
          "" -> []
          value -> [{unit, value}]
        end
      end)

    path = "#{prefix}.prescription_value"

    case present do
      [] ->
        {%{"prescription_value" => nil, "prescription_unit" => nil}, []}

      [{unit, value} | _rest] ->
        case coerce(path, value) do
          {:ok, number} ->
            {%{"prescription_value" => number, "prescription_unit" => unit}, []}

          :error ->
            {%{"prescription_value" => nil, "prescription_unit" => nil},
             [invalid_issue(path, value)]}
        end
    end
  end

  defp load(raw, prefix) do
    path = "#{prefix}.load_value"

    cond do
      truthy?(map_value_raw(raw, "bodyweight")) ->
        {%{"load_value" => nil, "load_mode" => "bw"}, []}

      present?(map_value_raw(raw, "load_percent_1rm")) ->
        coerce_load(path, map_value_raw(raw, "load_percent_1rm"), "pct_1rm")

      present?(map_value_raw(raw, "load_kg")) ->
        coerce_load(path, map_value_raw(raw, "load_kg"), "absolute")

      true ->
        {%{"load_value" => nil, "load_mode" => nil}, []}
    end
  end

  defp coerce_load(path, value, mode) do
    case coerce(path, value) do
      {:ok, number} -> {%{"load_value" => number, "load_mode" => mode}, []}
      :error -> {%{"load_value" => nil, "load_mode" => nil}, [invalid_issue(path, value)]}
    end
  end

  ## Assistant issues and suggestions

  defp normalize_assistant_issue(raw, workout, source) when is_map(raw) do
    with path when is_binary(path) <- raw |> map_value_raw("path") |> canonical_path(),
         true <- path_exists?(workout, path),
         severity <- assistant_severity(raw),
         suggestion <- assistant_suggestion(raw, path, source),
         # Only actionable advice reaches the coach: a remark without a fix
         # is dropped unless it reports a real error.
         true <- not is_nil(suggestion) or severity == "error" do
      [
        %{
          "path" => path,
          "code" => "assistant",
          "severity" => severity,
          "required" => required_path?(path),
          "message" => raw |> map_value_raw("message") |> clean_text(500),
          "params" => %{},
          "current_value" => get_path(workout, path),
          "suggestion" => suggestion
        }
      ]
    else
      _ -> []
    end
  end

  defp normalize_assistant_issue(_raw, _workout, _source), do: []

  # An assumption is a value the assistant inferred (a convention, a computed
  # number, an expanded abbreviation). Keep accepts the current value; Reject
  # clears the field like any other rejection.
  defp normalize_assumption(raw, workout) when is_map(raw) do
    with path when is_binary(path) <- raw |> map_value_raw("path") |> canonical_path(),
         true <- path_exists?(workout, path),
         value when not is_nil(value) <- get_path(workout, path),
         message when is_binary(message) <- raw |> map_value_raw("message") |> clean_text(500) do
      [
        %{
          "path" => path,
          "code" => "assumption",
          "severity" => "info",
          "required" => required_path?(path),
          "message" => message,
          "params" => %{},
          "current_value" => value,
          "suggestion" => %{"label" => nil, "value" => value, "text_edit" => nil}
        }
      ]
    else
      _ -> []
    end
  end

  defp normalize_assumption(_raw, _workout), do: []

  # Several inferred timer keys share one canonical field (timer_config): one
  # card explains them all, so Keep/Reject acts on the whole timer once.
  defp merge_assumptions(issues) do
    issues
    |> Enum.group_by(& &1["path"])
    |> Enum.map(fn {_path, [first | _rest] = group} ->
      %{first | "message" => Enum.map_join(group, " ", & &1["message"])}
    end)
    |> Enum.sort_by(fn issue -> Enum.find_index(issues, &(&1["path"] == issue["path"])) end)
  end

  defp assistant_severity(raw) do
    severity = raw |> map_value_raw("severity") |> to_string() |> String.downcase()
    if severity in @severities, do: severity, else: "warning"
  end

  defp assistant_suggestion(raw, path, source) do
    label = raw |> map_value_raw("suggestion_label") |> clean_text(160)

    text_edit =
      text_edit(map_value_raw(raw, "find_text"), map_value_raw(raw, "replace_text"), source)

    value =
      case coerce(path, assistant_value(raw)) do
        {:ok, value} -> value
        :error -> nil
      end

    if is_nil(value) and is_nil(text_edit) do
      nil
    else
      %{"label" => label, "value" => value, "text_edit" => text_edit}
    end
  end

  defp normalize_assistant_suggestion(raw, workout, _source) when is_map(raw) do
    with path when is_binary(path) <- raw |> map_value_raw("path") |> canonical_path(),
         true <- path_exists?(workout, path),
         true <- blank_value?(get_path(workout, path)),
         {:ok, value} <- coerce(path, assistant_value(raw)) do
      [
        %{
          "path" => path,
          "field" => path |> String.split(".") |> List.last(),
          "reason" => raw |> map_value_raw("reason") |> clean_text(300),
          "value" => value,
          "text_insert" => raw |> map_value_raw("insert_text") |> clean_text(300)
        }
      ]
    else
      _ -> []
    end
  end

  defp normalize_assistant_suggestion(_raw, _workout, _source), do: []

  # The assistant speaks in minutes for workout duration; canonical storage is
  # seconds.
  defp assistant_value(raw) do
    value = map_value_raw(raw, "suggested_value")
    path = map_value_raw(raw, "path")

    with true <- is_binary(path) and String.ends_with?(path, "estimated_duration_minutes"),
         {:ok, minutes} <- parse_number(value) do
      round(minutes * 60)
    else
      _ -> value
    end
  end

  defp recommended_suggestions(workout) do
    @recommended_workout_fields
    |> Enum.filter(&blank_value?(Map.get(workout, &1)))
    |> Enum.map(fn field ->
      %{
        "path" => field,
        "field" => field,
        "reason" => nil,
        "value" => nil,
        "text_insert" => nil
      }
    end)
  end

  defp text_edit(find, replace, source) when is_binary(find) and is_binary(replace) do
    find = String.trim(find)

    if find != "" and String.length(find) <= 500 and String.contains?(source, find) and
         find != replace do
      %{"find" => find, "replace" => String.slice(replace, 0, 500)}
    end
  end

  defp text_edit(_find, _replace, _source), do: nil

  # Assistant paths use its own friendlier field names; translate them to the
  # canonical field that stores the value.
  defp canonical_path(path) when is_binary(path) do
    segments =
      path
      |> String.trim()
      |> String.replace(~r/\[(\d+)\]/, ".\\1")
      |> String.trim_leading("workout.")
      |> String.split(".", trim: true)

    case segments do
      [field] ->
        field = translate_workout_field(field)
        if field in @workout_fields, do: field

      ["sections", index, field] ->
        field = if field in ["format", "timer"], do: "timer_config", else: field
        if integer?(index) and field in @section_fields, do: "sections.#{index}.#{field}"

      # A single timer key lives inside the section's timer config.
      ["sections", index, "timer", _key] ->
        if integer?(index), do: "sections.#{index}.timer_config"

      ["sections", index, "exercises", exercise_index, field] ->
        field = translate_exercise_field(field)

        if integer?(index) and integer?(exercise_index) and field in @exercise_fields,
          do: "sections.#{index}.exercises.#{exercise_index}.#{field}"

      _other ->
        nil
    end
  end

  defp canonical_path(_path), do: nil

  defp translate_workout_field("estimated_duration_minutes"), do: "estimated_duration_seconds"
  defp translate_workout_field(field), do: field

  defp translate_exercise_field(field)
       when field in ~w(reps duration_seconds calories distance_meters),
       do: "prescription_value"

  defp translate_exercise_field(field) when field in ~w(load_kg load_percent_1rm bodyweight),
    do: "load_value"

  defp translate_exercise_field(field), do: field

  ## Field specs and coercion

  defp field_spec(path) do
    case String.split(path, ".") do
      [field] -> workout_spec(field)
      ["sections", _index, "name"] -> {:string, 160}
      ["sections", _index, "note"] -> {:string, 2_000}
      ["sections", _index, "exercises", _exercise_index, field] -> exercise_spec(field)
      _other -> nil
    end
  end

  defp workout_spec("title"), do: {:string, 160}
  defp workout_spec("type"), do: {:enum, workout_types()}
  defp workout_spec("subtitle"), do: {:string, 240}
  defp workout_spec("description"), do: {:string, 10_000}
  defp workout_spec("difficulty"), do: {:enum, @difficulties}
  defp workout_spec("estimated_duration_seconds"), do: {:integer, 60}
  defp workout_spec("equipment"), do: :string_list
  defp workout_spec("tags"), do: :string_list
  defp workout_spec(_field), do: nil

  defp exercise_spec("name"), do: {:string, 160}
  defp exercise_spec("sets"), do: {:integer, 1}
  defp exercise_spec("interval_assignment"), do: {:integer, 1}
  defp exercise_spec("prescription_value"), do: {:integer, 1}
  defp exercise_spec("prescription_unit"), do: {:enum, @prescription_units}
  defp exercise_spec("load_value"), do: {:integer, 0}
  defp exercise_spec("load_mode"), do: {:enum, @load_modes}
  defp exercise_spec("rest_seconds"), do: {:integer, 0}
  defp exercise_spec("tempo"), do: {:string, 40}
  defp exercise_spec("note"), do: {:string, 2_000}
  defp exercise_spec(_field), do: nil

  defp coerce_value(_spec, nil), do: :error

  defp coerce_value({:string, max}, value) when is_binary(value) or is_number(value) do
    string = value |> to_string() |> String.trim()
    if string == "" or String.length(string) > max, do: :error, else: {:ok, string}
  end

  defp coerce_value({:enum, values}, value) when is_binary(value) or is_atom(value) do
    normalized =
      value |> to_string() |> String.trim() |> String.downcase() |> String.replace(" ", "_")

    normalized = if normalized == "all_levels", do: "all-levels", else: normalized
    if normalized in values, do: {:ok, normalized}, else: :error
  end

  defp coerce_value({:integer, min}, value) do
    case parse_number(value) do
      {:ok, number} ->
        integer = round(number)
        if integer >= min and integer <= 1_000_000, do: {:ok, integer}, else: :error

      :error ->
        :error
    end
  end

  defp coerce_value(:string_list, value) when is_binary(value),
    do: coerce_value(:string_list, String.split(value, ","))

  defp coerce_value(:string_list, value) when is_list(value) do
    items =
      value
      |> Enum.filter(&(is_binary(&1) or is_number(&1)))
      |> Enum.map(&(&1 |> to_string() |> String.trim()))
      |> Enum.reject(&(&1 == "" or String.length(&1) > 60))
      |> Enum.uniq()
      |> Enum.take(@max_list_items)

    if items == [], do: :error, else: {:ok, items}
  end

  defp coerce_value(_spec, _value), do: :error

  defp optional_value(path, value) do
    cond do
      blank_value?(value) ->
        {:ok, if(field_spec(path) == :string_list, do: [], else: nil)}

      true ->
        case coerce(path, value) do
          {:ok, normalized} -> {:ok, normalized}
          :error -> {:invalid, value}
        end
    end
  end

  defp required_string(path, value, min, max) do
    case coerce_value({:string, max}, value) do
      {:ok, string} ->
        if String.length(string) >= min,
          do: {string, []},
          else: {string, [issue(path, "too_short", "error", %{"min" => min}) |> mark_required()]}

      :error ->
        {nil, [required_issue(path, missing_code(path), value)]}
    end
  end

  defp missing_code("title"), do: "missing_title"

  defp missing_code(path) do
    if String.contains?(path, "exercises"),
      do: "missing_exercise_name",
      else: "missing_section_name"
  end

  defp parse_number(value) when is_integer(value), do: {:ok, value}
  defp parse_number(value) when is_float(value), do: {:ok, value}

  defp parse_number(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.replace(",", ".")

    case Float.parse(normalized) do
      {number, rest} when rest in ["", "kg", " kg", "s", "%", " %"] -> {:ok, number}
      _other -> :error
    end
  end

  defp parse_number(_value), do: :error

  ## Issues

  defp issue(path, code, severity, params) do
    %{
      "path" => path,
      "code" => code,
      "severity" => severity,
      "required" => required_path?(path),
      "message" => nil,
      "params" => params,
      "current_value" => nil,
      "suggestion" => nil
    }
  end

  defp required_issue(path, code, original) do
    path
    |> issue(code, "error", %{})
    |> Map.put("current_value", printable(original))
    |> mark_required()
  end

  defp invalid_issue(path, original) do
    path
    |> issue("invalid_value", "warning", %{"value" => printable(original)})
    |> Map.put("current_value", printable(original))
  end

  defp mark_required(issue), do: Map.put(issue, "required", true)

  defp overlaps?(find, covered) do
    Enum.any?(covered, &(String.contains?(&1, find) or String.contains?(find, &1)))
  end

  # Several text-only corrections can coexist; field issues stay one per path.
  defp dedupe_issues(issues) do
    issues
    |> Enum.uniq_by(fn issue ->
      if issue["path"] == "text",
        do: {"text", get_in(issue, ["suggestion", "text_edit", "find"])},
        else: issue["path"]
    end)
  end

  # Deterministic issues come first; an assistant issue on the same path only
  # survives when it is the sole report for that field.
  defp dedupe_by_path(entries) do
    {kept, _seen} =
      Enum.reduce(entries, {[], MapSet.new()}, fn entry, {acc, seen} ->
        if MapSet.member?(seen, entry["path"]),
          do: {acc, seen},
          else: {[entry | acc], MapSet.put(seen, entry["path"])}
      end)

    Enum.reverse(kept)
  end

  defp summary(workout, issues) do
    sections = workout["sections"]

    %{
      "sections" => length(sections),
      "exercises" => sections |> Enum.map(&length(&1["exercises"])) |> Enum.sum(),
      "errors" => Enum.count(issues, &(&1["severity"] == "error")),
      "warnings" => Enum.count(issues, &(&1["severity"] == "warning")),
      "blocking" => Enum.count(issues, &(&1["required"] and &1["severity"] == "error"))
    }
  end

  ## Path helpers

  defp path_exists?(workout, path) do
    case String.split(path, ".") do
      [field] -> Map.has_key?(workout, field)
      segments -> not is_nil(container(workout, Enum.drop(segments, -1)))
    end
  end

  defp get_path(workout, path) do
    segments = String.split(path, ".")

    case container(workout, Enum.drop(segments, -1)) do
      %{} = map -> Map.get(map, List.last(segments))
      _other -> nil
    end
  end

  defp container(value, []), do: value

  defp container(map, [key | rest]) when is_map(map),
    do: container(Map.get(map, key), rest)

  defp container(list, [index | rest]) when is_list(list) do
    case Integer.parse(index) do
      {position, ""} -> container(Enum.at(list, position), rest)
      _other -> nil
    end
  end

  defp container(_value, _segments), do: nil

  ## Generic helpers

  defp map_value(map, key) do
    case map_value_raw(map, key) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp list_value(map, key) do
    case map_value_raw(map, key) do
      list when is_list(list) -> list
      _other -> []
    end
  end

  defp map_value_raw(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, String.to_existing_atom(key), nil)
    end
  rescue
    ArgumentError -> nil
  end

  defp map_value_raw(_map, _key), do: nil

  defp to_key(nil), do: nil

  defp to_key(value),
    do: value |> to_string() |> String.trim() |> String.downcase() |> String.replace("-", "_")

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp blank_to_nil(value), do: value

  defp blank_value?(nil), do: true
  defp blank_value?([]), do: true
  defp blank_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_value?(_value), do: false

  defp present?(value), do: not blank_value?(value)

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false

  defp integer?(value), do: match?({_integer, ""}, Integer.parse(value))

  defp clean_text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> String.slice(text, 0, max)
    end
  end

  defp clean_text(_value, _max), do: nil

  defp printable(value) when is_binary(value), do: String.slice(value, 0, 200)
  defp printable(value) when is_number(value) or is_boolean(value), do: value
  defp printable(value) when is_list(value), do: value |> Enum.map(&printable/1) |> Enum.take(20)
  defp printable(_value), do: nil

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
