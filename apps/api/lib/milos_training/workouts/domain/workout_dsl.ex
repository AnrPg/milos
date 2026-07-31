defmodule MilosTraining.Workouts.Domain.WorkoutDsl do
  @moduledoc """
  Pure, deterministic parser and canonical formatter for workout DSL v1.

  This first grammar slice covers workout metadata, canonical section timers,
  section scoring, notes, headers, exercises, uniform prescriptions, and
  explicit per-set load progressions. Invalid or ambiguous input produces
  positioned diagnostics and never a guessed workout.
  """

  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  @version 1
  @workout_types ~w(crossfit strength gymnastics aerobics flexibility recovery)
  @score_types ~w(
    time reps weight rounds rounds+reps kcal hr_drop load
    accumulated_work_time pass_fail intervals_survived
  )

  @type diagnostic :: %{
          code: atom(),
          line: pos_integer(),
          column: pos_integer(),
          params: map()
        }

  @spec parse(binary()) :: {:ok, map()} | {:error, [diagnostic()]}
  def parse(source) when is_binary(source) do
    lines =
      source
      |> String.trim_leading("\uFEFF")
      |> String.split(~r/\r\n|\n|\r/, trim: false)

    state =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce(initial_state(), fn {line, line_number}, state ->
        process_line(state, line, line_number)
      end)
      |> flush_pending()
      |> finish_document(length(lines))

    diagnostics = Enum.reverse(state.diagnostics)

    if diagnostics == [] do
      {:ok,
       %{
         version: state.version,
         workout: state.workout,
         diagnostics: []
       }}
    else
      {:error, diagnostics}
    end
  end

  def parse(_source) do
    {:error, [diagnostic(:invalid_source, 1)]}
  end

  @spec format(map(), keyword()) :: binary()
  def format(workout, opts \\ []) when is_map(workout) do
    version = Keyword.get(opts, :version, @version)

    [
      "[workout]",
      "dsl-version: #{version}",
      scalar_line("title", value(workout, :title)),
      scalar_line("subtitle", value(workout, :subtitle)),
      scalar_line("type", value(workout, :type)),
      boolean_line("is-team-workout", value(workout, :is_team_workout)),
      format_notes(workout),
      workout
      |> value(:sections, [])
      |> Enum.map(&format_section/1),
      "[/workout]"
    ]
    |> flatten_lines()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp initial_state do
    %{
      stack: [],
      workout: %{sections: []},
      section: nil,
      item: nil,
      version: nil,
      pending: nil,
      diagnostics: []
    }
  end

  defp process_line(state, raw_line, line_number) do
    line = String.trim(raw_line)

    case state.pending do
      %{kind: :note} ->
        process_pending_note(state, line, line_number)

      %{kind: :sets} ->
        process_pending_sets(state, line, line_number)

      nil ->
        process_statement(state, line, line_number)
    end
  end

  defp process_pending_note(state, "", _line_number), do: flush_pending(state)

  defp process_pending_note(state, line, line_number) do
    if structural_statement?(line) do
      state
      |> flush_pending()
      |> process_statement(line, line_number)
    else
      update_in(state.pending.lines, &(&1 ++ [line]))
    end
  end

  defp process_pending_sets(state, line, line_number) do
    cond do
      line == "" ->
        flush_pending(state)

      String.starts_with?(line, "-") ->
        case parse_set_line(line) do
          {:ok, prescription} ->
            update_in(state.pending.sets, &(&1 ++ [prescription]))

          :error ->
            add_diagnostic(state, :invalid_set_prescription, line_number, %{value: line})
        end

      true ->
        state
        |> flush_pending()
        |> process_statement(line, line_number)
    end
  end

  defp process_statement(state, "", _line_number), do: state
  defp process_statement(state, "//" <> _comment, _line_number), do: state

  defp process_statement(state, line, line_number) do
    cond do
      Regex.match?(~r/^\[workout\]$/i, line) ->
        open_workout(state, line_number)

      match = Regex.run(~r/^\[section:\s*([^\]]+)\]$/i, line) ->
        open_section(state, Enum.at(match, 1), line_number)

      match = Regex.run(~r/^\[exercise:\s*([^\]]+)\]$/i, line) ->
        open_exercise(state, Enum.at(match, 1), line_number)

      Regex.match?(~r/^\[header\]$/i, line) ->
        open_header(state, line_number)

      match = Regex.run(~r/^\[\/(workout|section|exercise|header)\]$/i, line) ->
        close_block(state, Enum.at(match, 1) |> String.downcase(), line_number)

      match = Regex.run(~r/^(![a-z][a-z-]*):\s*$/i, line) ->
        start_note(state, Enum.at(match, 1) |> String.downcase(), line_number)

      match = Regex.run(~r/^([a-z][a-z0-9_-]*):\s*(.*)$/iu, line) ->
        put_statement(
          state,
          Vocabulary.canonical_key(Enum.at(match, 1)),
          String.trim(Enum.at(match, 2)),
          line_number
        )

      true ->
        add_diagnostic(state, :unexpected_text, line_number, %{value: line})
    end
  end

  defp open_workout(%{stack: []} = state, _line_number) do
    %{state | stack: [:workout], workout: %{sections: []}}
  end

  defp open_workout(state, line_number),
    do: add_diagnostic(state, :invalid_block_nesting, line_number, %{block: "workout"})

  defp open_section(%{stack: [:workout]} = state, raw_format, line_number) do
    format = Vocabulary.normalize_format(raw_format)

    state =
      if Vocabulary.valid_section_format?(format) do
        state
      else
        add_diagnostic(state, :unknown_section_format, line_number, %{format: raw_format})
      end

    section = %{
      name: nil,
      order: length(value(state.workout, :sections, [])) + 1,
      scoreable: false,
      score_config: nil,
      timer_config: %{type: format},
      exercises: []
    }

    %{state | stack: [:section, :workout], section: section}
  end

  defp open_section(state, _format, line_number),
    do: add_diagnostic(state, :invalid_block_nesting, line_number, %{block: "section"})

  defp open_exercise(%{stack: [:section, :workout]} = state, raw_name, line_number) do
    name = String.trim(raw_name)

    state =
      if name == "" do
        add_diagnostic(state, :missing_exercise_name, line_number)
      else
        state
      end

    item = %{
      item_type: "exercise",
      name: name,
      order: length(value(state.section, :exercises, [])) + 1,
      variations: []
    }

    %{state | stack: [:exercise, :section, :workout], item: item}
  end

  defp open_exercise(state, _name, line_number),
    do: add_diagnostic(state, :invalid_block_nesting, line_number, %{block: "exercise"})

  defp open_header(%{stack: [:section, :workout]} = state, _line_number) do
    item = %{
      item_type: "header",
      name: nil,
      order: length(value(state.section, :exercises, [])) + 1,
      set_prescriptions: [],
      variations: []
    }

    %{state | stack: [:header, :section, :workout], item: item}
  end

  defp open_header(state, line_number),
    do: add_diagnostic(state, :invalid_block_nesting, line_number, %{block: "header"})

  defp close_block(%{stack: [expected | _]} = state, expected_string, line_number)
       when is_atom(expected) do
    if Atom.to_string(expected) == expected_string do
      do_close_block(state, expected, line_number)
    else
      add_diagnostic(state, :mismatched_closing_block, line_number, %{
        expected: Atom.to_string(expected),
        received: expected_string
      })
    end
  end

  defp close_block(state, received, line_number),
    do: add_diagnostic(state, :unexpected_closing_block, line_number, %{received: received})

  defp do_close_block(state, kind, line_number) when kind in [:exercise, :header] do
    item = finalize_item(state.item)

    state =
      if blank?(value(item, :name)) do
        add_diagnostic(state, :missing_item_title, line_number, %{item_type: Atom.to_string(kind)})
      else
        state
      end

    section = Map.update!(state.section, :exercises, &(&1 ++ [item]))
    %{state | stack: tl(state.stack), section: section, item: nil}
  end

  defp do_close_block(state, :section, line_number) do
    state = validate_section(state, line_number)
    workout = Map.update!(state.workout, :sections, &(&1 ++ [state.section]))
    %{state | stack: tl(state.stack), workout: workout, section: nil}
  end

  defp do_close_block(state, :workout, line_number) do
    state
    |> validate_workout(line_number)
    |> Map.put(:stack, [])
  end

  defp start_note(state, marker, line_number) do
    if Vocabulary.note_marker?(marker) do
      %{state | pending: %{kind: :note, marker: marker, line: line_number, lines: []}}
    else
      add_diagnostic(state, :unknown_note_marker, line_number, %{marker: marker})
    end
  end

  defp put_statement(state, "dsl-version", raw_value, line_number) do
    if state.stack == [:workout] do
      case Integer.parse(raw_value) do
        {@version, ""} ->
          %{state | version: @version}

        {version, ""} ->
          add_diagnostic(state, :unsupported_dsl_version, line_number, %{version: version})

        _ ->
          add_diagnostic(state, :invalid_dsl_version, line_number, %{value: raw_value})
      end
    else
      invalid_scope(state, "dsl-version", line_number)
    end
  end

  defp put_statement(%{stack: [:workout]} = state, key, raw_value, line_number) do
    case key do
      "title" -> put_in(state.workout[:title], raw_value)
      "subtitle" -> put_in(state.workout[:subtitle], raw_value)
      "type" -> put_workout_type(state, raw_value, line_number)
      "is-team-workout" -> put_workout_boolean(state, raw_value, line_number)
      _ -> add_diagnostic(state, :unknown_workout_parameter, line_number, %{key: key})
    end
  end

  defp put_statement(%{stack: [:section, :workout]} = state, key, raw_value, line_number) do
    put_section_statement(state, key, raw_value, line_number)
  end

  defp put_statement(%{stack: [kind, :section, :workout]} = state, key, raw_value, line_number)
       when kind in [:exercise, :header] do
    put_item_statement(state, kind, key, raw_value, line_number)
  end

  defp put_statement(state, key, _raw_value, line_number),
    do: invalid_scope(state, key, line_number)

  defp put_workout_type(state, raw_value, line_number) do
    workout_type = raw_value |> String.downcase() |> String.replace("-", "_")

    if workout_type in @workout_types do
      put_in(state.workout[:type], workout_type)
    else
      add_diagnostic(state, :unknown_workout_type, line_number, %{type: raw_value})
    end
  end

  defp put_workout_boolean(state, raw_value, line_number) do
    case String.downcase(raw_value) do
      "true" -> put_in(state.workout[:is_team_workout], true)
      "false" -> put_in(state.workout[:is_team_workout], false)
      _ -> add_diagnostic(state, :invalid_boolean, line_number, %{value: raw_value})
    end
  end

  defp put_section_statement(state, "title", raw_value, _line_number),
    do: put_in(state.section[:name], raw_value)

  defp put_section_statement(state, "subtitle", raw_value, _line_number),
    do: put_in(state.section[:subtitle], raw_value)

  defp put_section_statement(state, "score", raw_value, line_number) do
    score_type = raw_value |> String.downcase() |> String.replace("-", "_")

    if score_type in @score_types do
      section =
        state.section
        |> Map.put(:scoreable, true)
        |> Map.put(:score_config, %{type: score_type})

      %{state | section: section}
    else
      add_diagnostic(state, :unknown_score_type, line_number, %{score: raw_value})
    end
  end

  defp put_section_statement(state, "score-unit", raw_value, _line_number) do
    score_config = Map.put(value(state.section, :score_config, %{}), :unit, raw_value)
    %{state | section: %{state.section | score_config: score_config, scoreable: true}}
  end

  defp put_section_statement(state, key, raw_value, line_number) do
    case Vocabulary.timer_field_for_dsl_key(key) do
      nil ->
        add_diagnostic(state, :unknown_section_parameter, line_number, %{key: key})

      field ->
        format = get_in(state, [:section, :timer_config, :type])

        if field in Vocabulary.allowed_timer_fields(format) do
          put_timer_value(state, field, raw_value, line_number)
        else
          add_diagnostic(state, :format_setting_not_allowed, line_number, %{
            key: key,
            format: format
          })
        end
    end
  end

  defp put_timer_value(state, field, raw_value, line_number) do
    case parse_typed_value(Vocabulary.timer_value_kind(field), raw_value) do
      {:ok, parsed} ->
        put_in(state.section[:timer_config][field], parsed)

      :error ->
        code =
          if Vocabulary.timer_value_kind(field) == :duration,
            do: :invalid_duration,
            else: :invalid_timer_value

        add_diagnostic(state, code, line_number, %{
          field: Vocabulary.dsl_key_for_timer_field(field),
          value: raw_value
        })
    end
  end

  defp put_item_statement(state, :header, "title", raw_value, _line_number),
    do: put_in(state.item[:name], raw_value)

  defp put_item_statement(state, :header, "subtitle", raw_value, _line_number),
    do: put_in(state.item[:subtitle], raw_value)

  defp put_item_statement(state, :header, key, _raw_value, line_number),
    do: add_diagnostic(state, :unknown_header_parameter, line_number, %{key: key})

  defp put_item_statement(state, :exercise, "sets", "", line_number),
    do: %{state | pending: %{kind: :sets, line: line_number, sets: []}}

  defp put_item_statement(state, :exercise, "sets", raw_value, line_number) do
    case positive_integer(raw_value) do
      {:ok, count} -> put_in(state.item[:sets], count)
      :error -> add_diagnostic(state, :invalid_set_count, line_number, %{value: raw_value})
    end
  end

  defp put_item_statement(state, :exercise, "reps", raw_value, line_number),
    do: put_prescription_value(state, raw_value, "reps", line_number)

  defp put_item_statement(state, :exercise, "duration", raw_value, line_number) do
    case parse_duration(raw_value) do
      {:ok, seconds} ->
        item =
          state.item
          |> Map.put(:prescription_value, seconds)
          |> Map.put(:prescription_unit, "secs")

        %{state | item: item}

      :error ->
        add_diagnostic(state, :invalid_duration, line_number, %{value: raw_value})
    end
  end

  defp put_item_statement(state, :exercise, "calories", raw_value, line_number),
    do: put_prescription_value(state, raw_value, "kcal", line_number)

  defp put_item_statement(state, :exercise, "load", raw_value, line_number) do
    case parse_load(raw_value) do
      {:ok, load_value, load_mode} ->
        item =
          state.item
          |> Map.put(:load_value, load_value)
          |> Map.put(:load_mode, load_mode)

        %{state | item: item}

      :error ->
        add_diagnostic(state, :invalid_load, line_number, %{value: raw_value})
    end
  end

  defp put_item_statement(state, :exercise, "tempo", raw_value, _line_number),
    do: put_in(state.item[:tempo], raw_value)

  defp put_item_statement(state, :exercise, "interval-assignment", raw_value, line_number) do
    case positive_integer(raw_value) do
      {:ok, assignment} -> put_in(state.item[:interval_assignment], assignment)
      :error -> add_diagnostic(state, :invalid_integer, line_number, %{value: raw_value})
    end
  end

  defp put_item_statement(state, :exercise, "rest-between-sets", raw_value, line_number) do
    case parse_duration(raw_value) do
      {:ok, seconds} -> put_in(state.item[:rest_seconds], seconds)
      :error -> add_diagnostic(state, :invalid_duration, line_number, %{value: raw_value})
    end
  end

  defp put_item_statement(state, :exercise, "progression", raw_value, line_number) do
    case raw_value |> String.downcase() |> String.replace("-", "_") do
      "explicit" -> put_in(state.item[:_progression], "explicit")
      "per_set" -> put_in(state.item[:_progression], "explicit")
      value -> add_diagnostic(state, :unsupported_progression, line_number, %{value: value})
    end
  end

  defp put_item_statement(state, :exercise, key, _raw_value, line_number) do
    code =
      if Vocabulary.exercise_key?(key),
        do: :unsupported_exercise_parameter,
        else: :unknown_exercise_parameter

    add_diagnostic(state, code, line_number, %{key: key})
  end

  defp put_prescription_value(state, raw_value, unit, line_number) do
    case positive_integer(raw_value) do
      {:ok, amount} ->
        item =
          state.item
          |> Map.put(:prescription_value, amount)
          |> Map.put(:prescription_unit, unit)

        %{state | item: item}

      :error ->
        add_diagnostic(state, :invalid_prescription_value, line_number, %{value: raw_value})
    end
  end

  defp flush_pending(%{pending: nil} = state), do: state

  defp flush_pending(%{pending: %{kind: :note} = pending} = state) do
    body =
      pending.lines
      |> Enum.join("\n")
      |> String.trim()

    state = %{state | pending: nil}

    if body == "" do
      add_diagnostic(state, :empty_note, pending.line, %{marker: pending.marker})
    else
      put_note(state, pending.marker, body)
    end
  end

  defp flush_pending(%{pending: %{kind: :sets} = pending} = state) do
    state = %{state | pending: nil}

    if pending.sets == [] do
      add_diagnostic(state, :empty_set_list, pending.line)
    else
      put_explicit_sets(state, pending.sets)
    end
  end

  defp put_note(state, marker, body) do
    note = %{type: String.trim_leading(marker, "!"), body: body}

    case state.stack do
      [:workout] ->
        workout =
          state.workout
          |> Map.update(:notes, [note], &(&1 ++ [note]))
          |> Map.put_new(:note, body)

        %{state | workout: workout}

      [:section, :workout] ->
        section =
          state.section
          |> Map.update(:notes, [note], &(&1 ++ [note]))
          |> Map.put_new(:note, body)

        %{state | section: section}

      [kind, :section, :workout] when kind in [:exercise, :header] ->
        item =
          state.item
          |> Map.update(:notes, [note], &(&1 ++ [note]))
          |> Map.put_new(:note, body)

        %{state | item: item}

      _ ->
        add_diagnostic(state, :invalid_note_scope, 1, %{marker: marker})
    end
  end

  defp put_explicit_sets(state, sets) do
    sets =
      sets
      |> Enum.with_index(1)
      |> Enum.map(fn {set, index} -> Map.put(set, :set_index, index) end)

    first = hd(sets)
    direction = infer_direction(Enum.map(sets, & &1.load_value))

    progression = %{
      mode: "per_set",
      direction: direction,
      start_value: first.load_value,
      start_mode: first.load_mode,
      step_value: 0,
      per_set_values: Enum.map(sets, & &1.load_value)
    }

    item =
      state.item
      |> Map.put(:sets, length(sets))
      |> Map.put(:set_prescriptions, sets)
      |> Map.put(:prescription_value, first.prescription_value)
      |> Map.put(:prescription_unit, first.prescription_unit)
      |> Map.put(:load_value, first.load_value)
      |> Map.put(:load_mode, first.load_mode)
      |> Map.put(:load_progression, progression)

    %{state | item: item}
  end

  defp finish_document(state, line_number) do
    state =
      if state.version == nil do
        add_diagnostic(state, :missing_dsl_version, 1)
      else
        state
      end

    Enum.reduce(state.stack, state, fn block, acc ->
      add_diagnostic(acc, :unclosed_block, max(line_number, 1), %{block: Atom.to_string(block)})
    end)
  end

  defp validate_workout(state, line_number) do
    state
    |> require_value(state.workout, :title, :missing_workout_title, line_number)
    |> require_value(state.workout, :type, :missing_workout_type, line_number)
  end

  defp validate_section(state, line_number) do
    state = require_value(state, state.section, :name, :missing_section_title, line_number)
    format = get_in(state, [:section, :timer_config, :type])

    Enum.reduce(Vocabulary.required_timer_fields(format), state, fn field, acc ->
      if blank?(get_in(acc, [:section, :timer_config, field])) do
        add_diagnostic(acc, :missing_required_timer_field, line_number, %{
          field: Vocabulary.dsl_key_for_timer_field(field),
          format: format
        })
      else
        acc
      end
    end)
  end

  defp require_value(state, container, key, code, line_number) do
    if blank?(value(container, key)) do
      add_diagnostic(state, code, line_number)
    else
      state
    end
  end

  defp finalize_item(item) do
    item
    |> Map.delete(:_progression)
  end

  defp structural_statement?(line) do
    line == "" or
      String.starts_with?(line, "[") or
      String.starts_with?(line, "!") or
      Regex.match?(~r/^[a-z][a-z0-9_-]*:\s*/iu, line)
  end

  defp parse_set_line(line) do
    regex =
      ~r/^-\s*(\d+)\s*(reps?|sec|secs|kcal)\s*@\s*(\d+(?:\.\d+)?)\s*(kg|%1rm|%)(?:\s*\[([^\]]+)\])?$/i

    case Regex.run(regex, line) do
      [_, prescription, raw_unit, raw_load, raw_load_unit] ->
        build_set_prescription(prescription, raw_unit, raw_load, raw_load_unit, nil)

      [_, prescription, raw_unit, raw_load, raw_load_unit, note] ->
        build_set_prescription(prescription, raw_unit, raw_load, raw_load_unit, note)

      _ ->
        :error
    end
  end

  defp build_set_prescription(prescription, raw_unit, raw_load, raw_load_unit, note) do
    with {:ok, prescription_value} <- positive_integer(prescription),
         {load_number, ""} <- Float.parse(raw_load) do
      load_value = normalize_number(load_number)
      load_mode = if String.downcase(raw_load_unit) == "kg", do: "absolute", else: "pct_1rm"

      {:ok,
       %{
         set_index: nil,
         prescription_value: prescription_value,
         prescription_unit: normalize_prescription_unit(raw_unit),
         load_value: load_value,
         load_mode: load_mode,
         note: blank_to_nil(note)
       }}
    else
      _ -> :error
    end
  end

  defp parse_duration(raw_value) do
    value = String.downcase(String.trim(raw_value))

    regex =
      ~r/(\d+(?:\.\d+)?)\s*(hours?|hour|h|minutes?|minute|mins?|min|m|seconds?|second|secs?|sec|s)/i

    matches = Regex.scan(regex, value)

    remainder =
      value
      |> String.replace(regex, "")
      |> String.replace(~r/\s+/, "")

    if matches == [] or remainder != "" do
      :error
    else
      seconds =
        Enum.reduce(matches, 0.0, fn [_, raw_number, unit], total ->
          {number, ""} = Float.parse(raw_number)

          multiplier =
            cond do
              String.starts_with?(unit, "h") -> 3600
              String.starts_with?(unit, "m") -> 60
              true -> 1
            end

          total + number * multiplier
        end)

      {:ok, round(seconds)}
    end
  end

  defp parse_load(raw_value) do
    case Regex.run(~r/^(\d+(?:\.\d+)?)\s*(kg|%1rm|%)$/i, String.trim(raw_value)) do
      [_, raw_number, raw_unit] ->
        {number, ""} = Float.parse(raw_number)
        mode = if String.downcase(raw_unit) == "kg", do: "absolute", else: "pct_1rm"
        {:ok, normalize_number(number), mode}

      _ ->
        :error
    end
  end

  defp parse_typed_value(:duration, value), do: parse_duration(value)

  defp parse_typed_value(:integer, value) do
    case positive_integer(value) do
      {:ok, number} -> {:ok, number}
      :error -> :error
    end
  end

  defp parse_typed_value(:string, value) do
    if String.trim(value) == "", do: :error, else: {:ok, String.trim(value)}
  end

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> :error
    end
  end

  defp infer_direction(values) do
    values
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value("increase", fn
      [left, right] when right > left -> "increase"
      [left, right] when right < left -> "decrease"
      _ -> nil
    end)
  end

  defp normalize_prescription_unit(raw_unit) do
    case String.downcase(raw_unit) do
      unit when unit in ["rep", "reps"] -> "reps"
      unit when unit in ["sec", "secs"] -> "secs"
      "kcal" -> "kcal"
    end
  end

  defp normalize_number(number) when trunc(number) == number, do: trunc(number)
  defp normalize_number(number), do: number

  defp invalid_scope(state, key, line_number),
    do: add_diagnostic(state, :invalid_parameter_scope, line_number, %{key: key})

  defp add_diagnostic(state, code, line_number, params \\ %{}) do
    diagnostic = diagnostic(code, line_number, params)
    update_in(state.diagnostics, &[diagnostic | &1])
  end

  defp diagnostic(code, line_number, params \\ %{}) do
    %{code: code, line: max(line_number, 1), column: 1, params: params}
  end

  defp format_section(section) do
    timer_config = value(section, :timer_config, %{})
    format = value(timer_config, :type, "untimed") |> to_string()

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
      timer_lines,
      format_score(section),
      format_notes(section),
      section
      |> value(:exercises, [])
      |> Enum.map(&format_item/1),
      "[/section]"
    ]
    |> flatten_lines()
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
    explicit_sets = value(item, :set_prescriptions, [])

    prescription_lines =
      if explicit_sets == [] do
        [
          scalar_line("sets", value(item, :sets)),
          format_uniform_prescription(item),
          format_load(item)
        ]
      else
        [
          "progression: explicit",
          "sets:",
          Enum.map(explicit_sets, &format_set_prescription/1)
        ]
      end

    [
      "[exercise: #{value(item, :name)}]",
      prescription_lines,
      scalar_line("tempo", value(item, :tempo)),
      duration_line("rest-between-sets", value(item, :rest_seconds)),
      scalar_line("interval-assignment", value(item, :interval_assignment)),
      format_notes(item),
      "[/exercise]"
    ]
    |> flatten_lines()
  end

  defp format_uniform_prescription(item) do
    case to_string(value(item, :prescription_unit, "")) do
      "reps" -> scalar_line("reps", value(item, :prescription_value))
      "secs" -> duration_line("duration", value(item, :prescription_value))
      "kcal" -> scalar_line("calories", value(item, :prescription_value))
      _ -> nil
    end
  end

  defp format_load(item) do
    case {value(item, :load_value), to_string(value(item, :load_mode, ""))} do
      {nil, _} -> nil
      {load, "absolute"} -> "load: #{format_number(load)} kg"
      {load, "pct_1rm"} -> "load: #{format_number(load)} %1rm"
      {_load, "bw"} -> "load: bodyweight"
      _ -> nil
    end
  end

  defp format_set_prescription(set) do
    prescription = value(set, :prescription_value)
    prescription_unit = value(set, :prescription_unit)
    load = value(set, :load_value)
    load_unit = if to_string(value(set, :load_mode)) == "pct_1rm", do: "%1rm", else: "kg"
    note = value(set, :note)

    "- #{prescription} #{prescription_unit} @ #{format_number(load)} #{load_unit}" <>
      if(blank?(note), do: "", else: " [#{note}]")
  end

  defp format_timer_line(field, value) do
    key = Vocabulary.dsl_key_for_timer_field(field)

    case Vocabulary.timer_value_kind(field) do
      :duration -> duration_line(key, value)
      _ -> scalar_line(key, value)
    end
  end

  defp format_score(section) do
    if value(section, :scoreable, false) do
      score_config = value(section, :score_config, %{})

      [
        scalar_line("score", value(score_config, :type)),
        scalar_line("score-unit", value(score_config, :unit))
      ]
    else
      []
    end
  end

  defp format_notes(container) do
    notes = value(container, :notes, [])

    cond do
      notes != [] ->
        Enum.map(notes, fn note ->
          ["!#{value(note, :type, "note")}:", value(note, :body)]
        end)

      not blank?(value(container, :note)) ->
        [["!note:", value(container, :note)]]

      true ->
        []
    end
  end

  defp duration_line(_key, nil), do: nil
  defp duration_line(key, seconds), do: "#{key}: #{format_duration(seconds)}"

  defp format_duration(seconds) when is_integer(seconds) and seconds >= 3600 do
    hours = div(seconds, 3600)
    remainder = rem(seconds, 3600)

    [hours > 0 && "#{hours} hour", format_minute_second_remainder(remainder)]
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.join(" ")
  end

  defp format_duration(seconds) when is_integer(seconds),
    do: format_minute_second_remainder(seconds)

  defp format_minute_second_remainder(seconds) when seconds >= 60 do
    minutes = div(seconds, 60)
    remainder = rem(seconds, 60)

    if remainder == 0, do: "#{minutes} min", else: "#{minutes} min #{remainder} sec"
  end

  defp format_minute_second_remainder(seconds), do: "#{seconds} sec"

  defp scalar_line(_key, nil), do: nil
  defp scalar_line(_key, ""), do: nil
  defp scalar_line(key, scalar), do: "#{key}: #{scalar}"

  defp boolean_line(_key, nil), do: nil
  defp boolean_line(key, value) when is_boolean(value), do: "#{key}: #{value}"

  defp flatten_lines(lines) do
    lines
    |> List.flatten()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp format_number(number) when is_float(number),
    do: :erlang.float_to_binary(number, [:compact])

  defp format_number(number), do: to_string(number)

  defp value(map, key, default \\ nil) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, found} -> found
      :error -> Map.get(map, Atom.to_string(key), default)
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: String.trim(value)
end
