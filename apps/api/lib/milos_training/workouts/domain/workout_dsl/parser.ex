defmodule MilosTraining.Workouts.Domain.WorkoutDsl.Parser do
  @moduledoc false

  alias MilosTraining.Workouts.Domain.WorkoutDsl.{ExerciseCatalog, Values, Vocabulary}

  @version 1
  @schema_version 1
  @max_source_bytes 200_000
  @max_lines 10_000
  @max_line_bytes 5_000
  @max_blocks 2_000
  @max_nesting 8
  @max_title_bytes 500
  @max_note_bytes 20_000
  @workout_types ~w(crossfit strength gymnastics aerobics flexibility recovery)
  @difficulties ~w(beginner intermediate advanced all-levels)
  @score_types ~w(
    time reps weight rounds rounds+reps kcal hr_drop load distance
    accumulated_work_time pass_fail intervals_survived
  )

  def parse(source) when is_binary(source) do
    source = String.trim_leading(source, "\uFEFF")

    with :ok <- validate_resource_limits(source) do
      lines = String.split(source, ~r/\r\n|\n|\r/, trim: false)

      state =
        lines
        |> Enum.with_index(1)
        |> Enum.reduce(initial_state(), fn {line, line_number}, state ->
          process_line(state, line, line_number)
        end)
        |> flush_pending()
        |> finish_document(max(length(lines), 1))

      diagnostics = Enum.reverse(state.diagnostics)
      errors = Enum.filter(diagnostics, &(&1.severity == :error))

      if errors == [] do
        {:ok,
         %{
           version: state.version,
           workout: state.result,
           diagnostics: diagnostics
         }}
      else
        {:error, diagnostics}
      end
    else
      {:error, diagnostic} -> {:error, [diagnostic]}
    end
  end

  def parse(_source), do: {:error, [diagnostic(:invalid_source, 1)]}

  defp initial_state do
    %{
      frames: [],
      result: nil,
      version: nil,
      pending: nil,
      diagnostics: [],
      block_count: 0,
      saw_root: false
    }
  end

  defp validate_resource_limits(source) do
    cond do
      byte_size(source) > @max_source_bytes ->
        {:error,
         diagnostic(:source_too_large, 1, %{
           maximum_bytes: @max_source_bytes,
           actual: byte_size(source)
         })}

      true ->
        lines = String.split(source, ~r/\r\n|\n|\r/, trim: false)

        cond do
          length(lines) > @max_lines ->
            {:error,
             diagnostic(:too_many_lines, 1, %{maximum: @max_lines, actual: length(lines)})}

          too_long = Enum.find_index(lines, &(byte_size(&1) > @max_line_bytes)) ->
            {:error, diagnostic(:line_too_long, too_long + 1, %{maximum_bytes: @max_line_bytes})}

          true ->
            :ok
        end
    end
  end

  defp process_line(state, raw_line, line_number) do
    line = String.trim(raw_line)

    case state.pending do
      %{kind: :note} -> process_pending_note(state, line, line_number)
      %{kind: :sets} -> process_pending_sets(state, line, line_number)
      nil -> process_statement(state, line, line_number)
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

  defp process_pending_sets(state, "", _line_number), do: flush_pending(state)

  defp process_pending_sets(state, line, line_number) do
    if String.starts_with?(line, "-") do
      case parse_set_line(line) do
        {:ok, prescription} ->
          update_in(state.pending.sets, &(&1 ++ [prescription]))

        {:error, reason} ->
          add_error(state, :invalid_set_prescription, line_number, %{
            value: line,
            reason: reason
          })
      end
    else
      state
      |> flush_pending()
      |> process_statement(line, line_number)
    end
  end

  defp process_statement(state, "", _line_number), do: state
  defp process_statement(state, "//" <> _comment, _line_number), do: state
  defp process_statement(state, "#" <> _comment, _line_number), do: state

  defp process_statement(state, line, line_number) do
    cond do
      Regex.match?(~r/^\[workout\]$/i, line) ->
        open_workout(state, line_number)

      match = Regex.run(~r/^\[section:\s*([^\]]+)\]$/i, line) ->
        open_section(state, Enum.at(match, 1), line_number)

      match = Regex.run(~r/^\[group:\s*(superset|alternating)\]$/i, line) ->
        open_group(state, Enum.at(match, 1), line_number)

      match = Regex.run(~r/^\[exercise:\s*([^\]]+)\]$/i, line) ->
        open_exercise(state, Enum.at(match, 1), line_number)

      Regex.match?(~r/^\[header\]$/i, line) ->
        open_header(state, line_number)

      match = Regex.run(~r/^\[scale:\s*([^\]]+)\]$/i, line) ->
        open_scale(state, Enum.at(match, 1), line_number)

      match = Regex.run(~r/^\[\/(workout|section|group|exercise|header|scale)\]$/i, line) ->
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
        add_error(state, :unexpected_text, line_number, %{value: line})
    end
  end

  defp open_workout(%{frames: [], saw_root: false} = state, line_number) do
    frame =
      frame(:workout, line_number, %{
        sections: [],
        notes: [],
        equipment: [],
        tags: [],
        workout_metadata: %{"schema_version" => @schema_version},
        is_team_workout: false
      })

    push_frame(%{state | saw_root: true}, frame, line_number)
  end

  defp open_workout(state, line_number),
    do: add_error(state, :invalid_block_nesting, line_number, %{block: "workout"})

  defp open_section(state, raw_format, line_number) do
    if current_kind(state) in [:workout, :section] do
      parent = hd(state.frames)
      section_index = length(value(parent.data, :sections, [])) + 1
      path = value(parent.context, :path, []) ++ [section_index]

      case Vocabulary.resolve_format(raw_format) do
        {:ok, format, composition} ->
          metadata = if composition, do: %{"composition" => composition}, else: %{}

          data = %{
            name: nil,
            scoreable: false,
            score_config: nil,
            timer_config: %{type: format},
            exercises: [],
            sections: [],
            notes: [],
            section_metadata: metadata
          }

          push_frame(state, frame(:section, line_number, data, %{path: path}), line_number)

        {:error, :unknown_format} ->
          state
          |> add_error(:unknown_section_format, line_number, %{format: raw_format})
          |> push_frame(
            frame(
              :section,
              line_number,
              %{
                name: nil,
                scoreable: false,
                score_config: nil,
                timer_config: %{type: Vocabulary.normalize_format(raw_format)},
                exercises: [],
                sections: [],
                notes: [],
                section_metadata: %{}
              },
              %{path: path}
            ),
            line_number
          )
      end
    else
      add_error(state, :invalid_block_nesting, line_number, %{block: "section"})
    end
  end

  defp open_group(state, raw_type, line_number) do
    if current_kind(state) == :section do
      type = String.downcase(raw_type)
      section_frame = hd(state.frames)

      group_index =
        section_frame.data
        |> value(:exercises, [])
        |> Enum.map(&group_identity/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()
        |> Kernel.+(1)

      path = value(section_frame.context, :path, []) ++ [group_index]

      push_frame(
        state,
        frame(
          :group,
          line_number,
          %{
            type: type,
            title: nil,
            sets: nil,
            rest_between_groups_seconds: nil,
            notes: [],
            items: []
          },
          %{path: path}
        ),
        line_number
      )
    else
      add_error(state, :invalid_block_nesting, line_number, %{block: "group"})
    end
  end

  defp open_exercise(state, raw_name, line_number) do
    if current_kind(state) in [:section, :group] do
      name = raw_name |> text_value() |> elem_or(raw_name) |> String.trim()

      {state, data, catalog} =
        case ExerciseCatalog.resolve(name) do
          {:ok, entry, :canonical} ->
            {state, base_exercise(entry.label, entry.id), entry}

          {:ok, entry, :alias} ->
            state =
              add_warning(state, :exercise_alias_resolved, line_number, %{
                alias: name,
                canonical: entry.label,
                exercise_ref: entry.id
              })

            data =
              entry.label
              |> base_exercise(entry.id)
              |> put_metadata_value("catalog_alias", name)

            {state, data, entry}

          {:error, {:ambiguous, ids}} ->
            state =
              add_error(state, :ambiguous_exercise_reference, line_number, %{
                name: name,
                matches: ids
              })

            {state, base_exercise(name, nil), nil}

          {:error, :not_found} ->
            state = add_error(state, :unresolved_exercise_reference, line_number, %{name: name})
            {state, base_exercise(name, nil), nil}
        end

      push_frame(state, frame(:exercise, line_number, data, %{catalog: catalog}), line_number)
    else
      add_error(state, :invalid_block_nesting, line_number, %{block: "exercise"})
    end
  end

  defp open_header(state, line_number) do
    if current_kind(state) == :section do
      data = %{
        item_type: "header",
        name: nil,
        subtitle: nil,
        set_prescriptions: [],
        variations: [],
        notes: []
      }

      push_frame(state, frame(:header, line_number, data), line_number)
    else
      add_error(state, :invalid_block_nesting, line_number, %{block: "header"})
    end
  end

  defp open_scale(state, raw_slug, line_number) do
    if current_kind(state) == :exercise do
      case Values.slug(raw_slug) do
        {:ok, slug} ->
          catalog = state.frames |> hd() |> get_in([:context, :catalog])

          data = %{
            scale_level_slug: slug,
            notes: [],
            prescription_metadata: %{},
            excluded: false
          }

          push_frame(state, frame(:scale, line_number, data, %{catalog: catalog}), line_number)

        :error ->
          add_error(state, :invalid_scale_slug, line_number, %{value: raw_slug})
      end
    else
      add_error(state, :invalid_block_nesting, line_number, %{block: "scale"})
    end
  end

  defp push_frame(state, frame, line_number) do
    cond do
      length(state.frames) >= @max_nesting ->
        add_error(state, :nesting_too_deep, line_number, %{maximum: @max_nesting})

      state.block_count >= @max_blocks ->
        add_error(state, :too_many_blocks, line_number, %{maximum: @max_blocks})

      true ->
        %{state | frames: [frame | state.frames], block_count: state.block_count + 1}
    end
  end

  defp close_block(%{frames: []} = state, received, line_number),
    do: add_error(state, :unexpected_closing_block, line_number, %{received: received})

  defp close_block(state, received, line_number) do
    expected = state.frames |> hd() |> Map.fetch!(:kind) |> Atom.to_string()

    if expected == received do
      do_close_block(state, line_number)
    else
      add_error(state, :mismatched_closing_block, line_number, %{
        expected: expected,
        received: received
      })
    end
  end

  defp do_close_block(state, line_number) do
    [frame | parents] = state.frames
    state = %{state | frames: parents}
    {state, frame} = finalize_frame(state, frame, line_number)
    attach_frame(state, frame, line_number)
  end

  defp finalize_frame(state, %{kind: :workout} = frame, line_number) do
    state =
      state
      |> require_frame_value(frame, :title, :missing_workout_title, line_number)
      |> require_frame_value(frame, :type, :missing_workout_type, line_number)

    {state, frame}
  end

  defp finalize_frame(state, %{kind: :section} = frame, line_number) do
    state = require_frame_value(state, frame, :name, :missing_section_title, line_number)
    format = value(frame.data.timer_config, :type)

    state =
      Enum.reduce(Vocabulary.required_dsl_timer_fields(format), state, fn field, acc ->
        if blank?(value(frame.data.timer_config, field)) do
          add_error(acc, :missing_required_timer_field, line_number, %{
            field: Vocabulary.dsl_key_for_timer_field(field),
            format: format
          })
        else
          acc
        end
      end)

    state =
      state
      |> validate_section_score(frame, line_number)
      |> validate_format_specific_section(frame, line_number)

    data =
      frame.data
      |> Map.update!(:exercises, &assign_order/1)
      |> Map.update!(:sections, &assign_order/1)

    {state, %{frame | data: data}}
  end

  defp finalize_frame(state, %{kind: :group} = frame, line_number) do
    state =
      if length(frame.data.items) < 2,
        do: add_error(state, :group_requires_multiple_exercises, line_number),
        else: state

    title = frame.data.title || "#{String.capitalize(frame.data.type)} group"
    path = frame.context |> value(:path, []) |> Enum.join(".")
    group_id = deterministic_uuid("group:#{path}:#{frame.data.type}")

    config =
      %{
        "type" => frame.data.type,
        "title" => title,
        "sets" => frame.data.sets,
        "rest_between_groups_seconds" => frame.data.rest_between_groups_seconds,
        "notes" => frame.data.notes
      }
      |> reject_nil_values()

    group_field =
      if frame.data.type == "superset",
        do: :superset_group_id,
        else: :alternating_group_id

    items =
      Enum.map(frame.data.items, fn item ->
        item
        |> Map.put(group_field, group_id)
        |> Map.put(:group_config, config)
        |> inherit_group_sets(frame.data.sets)
      end)

    {state, %{frame | data: %{frame.data | title: title, items: items}}}
  end

  defp finalize_frame(state, %{kind: :exercise} = frame, line_number) do
    state =
      if blank?(frame.data.name),
        do: add_error(state, :missing_exercise_name, line_number),
        else: state

    {state, data} = finalize_prescriptions(state, frame.data, frame, line_number)
    state = validate_capabilities(state, frame, line_number)
    {state, %{frame | data: data}}
  end

  defp finalize_frame(state, %{kind: :scale} = frame, line_number) do
    {state, data} = finalize_prescriptions(state, frame.data, frame, line_number)

    meaningful_keys =
      data
      |> Map.drop([:scale_level_slug, :notes, :prescription_metadata, :excluded])
      |> Enum.reject(fn {_key, value} -> blank?(value) end)

    has_metadata = map_size(value(data, :prescription_metadata, %{})) > 0
    has_notes = value(data, :notes, []) != []

    state =
      if meaningful_keys == [] and not has_metadata and not has_notes and not data.excluded,
        do:
          add_error(state, :empty_scale_variation, line_number, %{scale: data.scale_level_slug}),
        else: state

    state = validate_capabilities(state, frame, line_number)
    {state, %{frame | data: data}}
  end

  defp finalize_frame(state, %{kind: :header} = frame, line_number) do
    state =
      if blank?(frame.data.name),
        do: add_error(state, :missing_item_title, line_number, %{item_type: "header"}),
        else: state

    {state, frame}
  end

  defp attach_frame(state, %{kind: :workout, data: data}, _line_number) do
    if state.frames == [] do
      %{state | result: data}
    else
      add_error(state, :invalid_block_nesting, 1, %{block: "workout"})
    end
  end

  defp attach_frame(state, %{kind: :section, data: data}, line_number) do
    case current_kind(state) do
      :workout ->
        update_top_data(state, &Map.update!(&1, :sections, fn items -> items ++ [data] end))

      :section ->
        update_top_data(state, &Map.update!(&1, :sections, fn items -> items ++ [data] end))

      _ ->
        add_error(state, :invalid_block_nesting, line_number, %{block: "section"})
    end
  end

  defp attach_frame(state, %{kind: kind, data: data}, line_number)
       when kind in [:exercise, :header] do
    case current_kind(state) do
      :section ->
        update_top_data(state, &Map.update!(&1, :exercises, fn items -> items ++ [data] end))

      :group when kind == :exercise ->
        update_top_data(state, &Map.update!(&1, :items, fn items -> items ++ [data] end))

      _ ->
        add_error(state, :invalid_block_nesting, line_number, %{block: Atom.to_string(kind)})
    end
  end

  defp attach_frame(state, %{kind: :group, data: data}, line_number) do
    if current_kind(state) == :section do
      update_top_data(state, &Map.update!(&1, :exercises, fn items -> items ++ data.items end))
    else
      add_error(state, :invalid_block_nesting, line_number, %{block: "group"})
    end
  end

  defp attach_frame(state, %{kind: :scale, data: data}, line_number) do
    if current_kind(state) == :exercise do
      update_top_data(
        state,
        &Map.update!(&1, :variations, fn variations -> variations ++ [data] end)
      )
    else
      add_error(state, :invalid_block_nesting, line_number, %{block: "scale"})
    end
  end

  defp start_note(state, marker, line_number) do
    cond do
      state.frames == [] ->
        add_error(state, :invalid_note_scope, line_number, %{marker: marker})

      not Vocabulary.note_marker?(marker) ->
        add_error(state, :unknown_note_marker, line_number, %{marker: marker})

      true ->
        %{state | pending: %{kind: :note, marker: marker, line: line_number, lines: []}}
    end
  end

  defp put_statement(%{frames: []} = state, key, _raw_value, line_number),
    do: add_error(state, :invalid_parameter_scope, line_number, %{key: key})

  defp put_statement(state, key, raw_value, line_number) do
    case current_kind(state) do
      :workout ->
        put_workout_statement(state, key, raw_value, line_number)

      :section ->
        put_section_statement(state, key, raw_value, line_number)

      :group ->
        put_group_statement(state, key, raw_value, line_number)

      :header ->
        put_header_statement(state, key, raw_value, line_number)

      kind when kind in [:exercise, :scale] ->
        put_exercise_statement(state, kind, key, raw_value, line_number)

      _ ->
        add_error(state, :invalid_parameter_scope, line_number, %{key: key})
    end
  end

  defp put_workout_statement(state, "dsl-version", raw_value, line_number) do
    put_once(state, "dsl-version", line_number, fn state ->
      case Values.integer(raw_value) do
        {:ok, @version} ->
          %{state | version: @version}

        {:ok, version} ->
          add_error(state, :unsupported_dsl_version, line_number, %{version: version})

        :error ->
          add_error(state, :invalid_dsl_version, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_workout_statement(state, key, raw_value, line_number)
       when key in ["title", "subtitle", "description"] do
    with_text(state, key, raw_value, line_number, fn value ->
      field = if key == "title", do: :title, else: String.to_existing_atom(key)
      put_top_data(state, field, value)
    end)
  end

  defp put_workout_statement(state, "type", raw_value, line_number) do
    value = raw_value |> String.downcase() |> String.replace("-", "_")

    put_once(state, "type", line_number, fn state ->
      if value in @workout_types,
        do: put_top_data(state, :type, value),
        else: add_error(state, :unknown_workout_type, line_number, %{type: raw_value})
    end)
  end

  defp put_workout_statement(state, "difficulty", raw_value, line_number) do
    value = raw_value |> String.downcase() |> String.replace("_", "-")

    put_once(state, "difficulty", line_number, fn state ->
      if value in @difficulties,
        do: put_top_data(state, :difficulty, value),
        else: add_error(state, :invalid_difficulty, line_number, %{value: raw_value})
    end)
  end

  defp put_workout_statement(state, "estimated-duration", raw_value, line_number),
    do:
      put_parsed(
        state,
        "estimated-duration",
        raw_value,
        line_number,
        &Values.duration/1,
        :estimated_duration_seconds,
        :invalid_duration
      )

  defp put_workout_statement(state, key, raw_value, line_number)
       when key in ["equipment", "tags"] do
    field = if key == "equipment", do: :equipment, else: :tags

    put_parsed(state, key, raw_value, line_number, &Values.list/1, field, :invalid_list)
  end

  defp put_workout_statement(state, "is-team-workout", raw_value, line_number),
    do:
      put_parsed(
        state,
        "is-team-workout",
        raw_value,
        line_number,
        &Values.boolean/1,
        :is_team_workout,
        :invalid_boolean
      )

  defp put_workout_statement(state, key, raw_value, line_number)
       when key in [
              "target-population",
              "objective",
              "location",
              "modality",
              "program-position"
            ] do
    metadata_key = String.replace(key, "-", "_")

    with_text(state, key, raw_value, line_number, fn text ->
      put_top_metadata(state, :workout_metadata, metadata_key, text)
    end)
  end

  defp put_workout_statement(state, "default-scale", raw_value, line_number) do
    put_once(state, "default-scale", line_number, fn state ->
      case Values.slug(raw_value) do
        {:ok, slug} -> put_top_metadata(state, :workout_metadata, "default_scale", slug)
        :error -> add_error(state, :invalid_scale_slug, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_workout_statement(state, "source-revision", raw_value, line_number) do
    put_parsed_metadata(
      state,
      "source-revision",
      raw_value,
      line_number,
      &Values.integer(&1, minimum: 0),
      :workout_metadata,
      "source_revision",
      :invalid_integer
    )
  end

  defp put_workout_statement(state, "canonical-schema-version", raw_value, line_number) do
    put_once(state, "canonical-schema-version", line_number, fn state ->
      case Values.integer(raw_value) do
        {:ok, @schema_version} ->
          put_top_metadata(state, :workout_metadata, "schema_version", @schema_version)

        {:ok, version} ->
          add_error(state, :unsupported_canonical_schema_version, line_number, %{version: version})

        :error ->
          add_error(state, :invalid_canonical_schema_version, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_workout_statement(state, key, _raw_value, line_number) do
    code =
      if Vocabulary.workout_key?(key),
        do: :unsupported_workout_parameter,
        else: :unknown_workout_parameter

    add_error(state, code, line_number, %{key: key})
  end

  defp put_section_statement(state, key, raw_value, line_number)
       when key in ["title", "subtitle"] do
    field = if key == "title", do: :name, else: :subtitle
    with_text(state, key, raw_value, line_number, &put_top_data(state, field, &1))
  end

  defp put_section_statement(state, "score", raw_value, line_number) do
    score = normalize_score_type(raw_value)

    put_once(state, "score", line_number, fn state ->
      if score in @score_types do
        update_top_data(state, fn data ->
          data
          |> Map.put(:scoreable, true)
          |> Map.put(:score_config, %{type: score})
        end)
      else
        add_error(state, :unknown_score_type, line_number, %{score: raw_value})
      end
    end)
  end

  defp put_section_statement(state, key, raw_value, line_number)
       when key in ["score-unit", "score-label"] do
    with_text(state, key, raw_value, line_number, fn text ->
      field = if key == "score-unit", do: :unit, else: :label

      update_top_data(state, fn data ->
        score_config = Map.put(value(data, :score_config, %{}), field, text)
        %{data | scoreable: true, score_config: score_config}
      end)
    end)
  end

  defp put_section_statement(state, "composition", raw_value, line_number) do
    normalized = raw_value |> String.downcase() |> String.replace("-", "_")

    put_once(state, "composition", line_number, fn state ->
      if normalized in ~w(straight_sets rounds circuit stations) do
        put_top_metadata(state, :section_metadata, "composition", normalized)
      else
        add_error(state, :invalid_section_composition, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_section_statement(state, "rest-before-next-section", raw_value, line_number),
    do:
      put_parsed(
        state,
        "rest-before-next-section",
        raw_value,
        line_number,
        &Values.duration/1,
        :rest_before_next_section_seconds,
        :invalid_duration
      )

  defp put_section_statement(state, key, raw_value, line_number)
       when key in [
              "rest-between-exercises",
              "rest-between-rounds",
              "rest-between-groups"
            ] do
    metadata_key = String.replace(key, "-", "_") <> "_seconds"

    put_parsed_metadata(
      state,
      key,
      raw_value,
      line_number,
      &Values.duration/1,
      :section_metadata,
      metadata_key,
      :invalid_duration
    )
  end

  defp put_section_statement(state, "transition-time" = key, raw_value, line_number) do
    format = state.frames |> hd() |> get_in([:data, :timer_config, :type])

    if :transition_seconds in Vocabulary.allowed_timer_fields(format) do
      put_timer_value(state, key, :transition_seconds, raw_value, line_number)
    else
      put_parsed_metadata(
        state,
        key,
        raw_value,
        line_number,
        &Values.duration/1,
        :section_metadata,
        "transition_seconds",
        :invalid_duration
      )
    end
  end

  defp put_section_statement(state, "auto-advance", raw_value, line_number) do
    put_parsed_metadata(
      state,
      "auto-advance",
      raw_value,
      line_number,
      &Values.boolean/1,
      :section_metadata,
      "auto_advance",
      :invalid_boolean
    )
  end

  defp put_section_statement(state, "recovery-condition" = key, raw_value, line_number) do
    format = state.frames |> hd() |> get_in([:data, :timer_config, :type])

    if :recovery_condition in Vocabulary.allowed_timer_fields(format) do
      put_timer_value(state, key, :recovery_condition, raw_value, line_number)
    else
      with_text(state, key, raw_value, line_number, fn text ->
        put_top_metadata(state, :section_metadata, "recovery_condition", text)
      end)
    end
  end

  defp put_section_statement(state, "target-condition" = key, raw_value, line_number) do
    metadata_key = String.replace(key, "-", "_")

    with_text(state, key, raw_value, line_number, fn text ->
      put_top_metadata(state, :section_metadata, metadata_key, text)
    end)
  end

  defp put_section_statement(state, key, raw_value, line_number) do
    case Vocabulary.timer_field_for_dsl_key(key) do
      nil ->
        add_error(state, :unknown_section_parameter, line_number, %{key: key})

      field ->
        format = state.frames |> hd() |> get_in([:data, :timer_config, :type])

        if field in Vocabulary.allowed_timer_fields(format) do
          put_timer_value(state, key, field, raw_value, line_number)
        else
          add_error(state, :format_setting_not_allowed, line_number, %{
            key: key,
            format: format
          })
        end
    end
  end

  defp put_timer_value(state, key, field, raw_value, line_number) do
    {parser, error_code} =
      case Vocabulary.timer_value_kind(field) do
        :duration ->
          {&Values.duration/1, :invalid_duration}

        :distance ->
          {&Values.distance/1, :invalid_distance}

        :integer ->
          {&Values.integer/1, :invalid_integer}

        :enum ->
          {fn value ->
             normalized = value |> String.downcase() |> String.replace("-", "_")

             if normalized in Vocabulary.timer_enum_values(field),
               do: {:ok, normalized},
               else: :error
           end, :invalid_enum_value}

        :string ->
          {fn value -> text_value(value) end, :invalid_text_value}
      end

    put_once(state, key, line_number, fn state ->
      case parser.(raw_value) do
        {:ok, parsed} ->
          update_top_data(state, fn data ->
            Map.update!(data, :timer_config, &Map.put(&1, field, parsed))
          end)

        :error ->
          add_error(state, error_code, line_number, %{key: key, value: raw_value})
      end
    end)
  end

  defp put_group_statement(state, "title", raw_value, line_number),
    do: with_text(state, "title", raw_value, line_number, &put_top_data(state, :title, &1))

  defp put_group_statement(state, "sets", raw_value, line_number),
    do:
      put_parsed(
        state,
        "sets",
        raw_value,
        line_number,
        &Values.integer/1,
        :sets,
        :invalid_set_count
      )

  defp put_group_statement(state, "rest-between-groups", raw_value, line_number),
    do:
      put_parsed(
        state,
        "rest-between-groups",
        raw_value,
        line_number,
        &Values.duration/1,
        :rest_between_groups_seconds,
        :invalid_duration
      )

  defp put_group_statement(state, key, _raw_value, line_number),
    do: add_error(state, :unknown_group_parameter, line_number, %{key: key})

  defp put_header_statement(state, key, raw_value, line_number)
       when key in ["title", "subtitle"] do
    field = if key == "title", do: :name, else: :subtitle
    with_text(state, key, raw_value, line_number, &put_top_data(state, field, &1))
  end

  defp put_header_statement(state, key, _raw_value, line_number),
    do: add_error(state, :unknown_header_parameter, line_number, %{key: key})

  defp put_exercise_statement(state, _kind, "sets", "", line_number) do
    put_once(state, "sets", line_number, fn state ->
      %{state | pending: %{kind: :sets, line: line_number, sets: []}}
    end)
  end

  defp put_exercise_statement(state, _kind, "sets", raw_value, line_number),
    do:
      put_parsed(
        state,
        "sets",
        raw_value,
        line_number,
        &Values.integer/1,
        :sets,
        :invalid_set_count,
        "sets"
      )

  defp put_exercise_statement(state, _kind, "subtitle", raw_value, line_number),
    do: with_text(state, "subtitle", raw_value, line_number, &put_top_data(state, :subtitle, &1))

  defp put_exercise_statement(state, _kind, "reps", raw_value, line_number),
    do: put_prescription(state, "reps", raw_value, "reps", &Values.integer/1, line_number)

  defp put_exercise_statement(state, _kind, "duration", raw_value, line_number),
    do: put_prescription(state, "duration", raw_value, "secs", &Values.duration/1, line_number)

  defp put_exercise_statement(state, _kind, "calories", raw_value, line_number),
    do: put_prescription(state, "calories", raw_value, "kcal", &Values.integer/1, line_number)

  defp put_exercise_statement(state, _kind, "distance", raw_value, line_number),
    do: put_prescription(state, "distance", raw_value, "meters", &Values.distance/1, line_number)

  defp put_exercise_statement(state, _kind, "prescription", raw_value, line_number) do
    put_once(state, "prescription", line_number, fn state ->
      case parse_compact_prescription(raw_value) do
        {:ok, fields} ->
          state
          |> update_top_data(&apply_compact_fields(&1, fields))
          |> mark_capability("sets")
          |> mark_capability("reps")
          |> maybe_mark_load(fields)

        {:error, reason} ->
          add_error(state, :invalid_compact_prescription, line_number, %{
            value: raw_value,
            reason: reason
          })
      end
    end)
  end

  defp put_exercise_statement(state, _kind, "load", raw_value, line_number) do
    put_once(state, "load", line_number, fn state ->
      case Values.load_range(raw_value) do
        {:ok, start_load, end_load} ->
          state
          |> update_top_data(fn data ->
            data
            |> put_load(start_load)
            |> Map.put(:_load_end, end_load)
          end)
          |> mark_capability("load")

        :error ->
          case Values.load(raw_value) do
            {:ok, load} ->
              state
              |> update_top_data(&put_load(&1, load))
              |> mark_capability("load")

            :error ->
              add_error(state, :invalid_load, line_number, %{value: raw_value})
          end
      end
    end)
  end

  defp put_exercise_statement(state, _kind, "load-start", raw_value, line_number) do
    put_once(state, "load-start", line_number, fn state ->
      case Values.load(raw_value) do
        {:ok, load} ->
          state
          |> update_top_data(fn data -> data |> put_load(load) |> Map.put(:_load_start, load) end)
          |> mark_capability("load")

        :error ->
          add_error(state, :invalid_load, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_exercise_statement(state, _kind, "load-step", raw_value, line_number) do
    put_once(state, "load-step", line_number, fn state ->
      case Values.load(raw_value, signed: true) do
        {:ok, load} ->
          state
          |> update_top_data(&Map.put(&1, :_load_step, load))
          |> mark_capability("load")

        :error ->
          add_error(state, :invalid_load_step, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_exercise_statement(state, _kind, "progression", raw_value, line_number) do
    normalized = raw_value |> String.downcase() |> String.replace("-", "_")

    put_once(state, "progression", line_number, fn state ->
      if normalized in ["linear", "explicit", "per_set"] do
        state
        |> update_top_data(
          &Map.put(
            &1,
            :_progression,
            if(normalized == "per_set", do: "explicit", else: normalized)
          )
        )
        |> mark_capability("progression")
      else
        add_error(state, :unsupported_progression, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_exercise_statement(state, kind, "variation", raw_value, line_number) do
    with_text(state, "variation", raw_value, line_number, fn text ->
      if kind == :scale,
        do: put_top_data(state, :exercise_name_override, text),
        else: put_top_metadata(state, :prescription_metadata, "variation", text)
    end)
  end

  defp put_exercise_statement(state, _kind, "tempo", raw_value, line_number) do
    with_text(state, "tempo", raw_value, line_number, fn text ->
      state |> put_top_data(:tempo, text) |> mark_capability("tempo")
    end)
  end

  defp put_exercise_statement(state, _kind, "interval-assignment", raw_value, line_number) do
    put_once(state, "interval-assignment", line_number, fn state ->
      assignment =
        case String.downcase(String.trim(raw_value)) do
          "odd" -> {:ok, 1}
          "even" -> {:ok, 2}
          value -> Values.integer(value)
        end

      case assignment do
        {:ok, slot} ->
          state
          |> put_top_data(:interval_assignment, slot)
          |> mark_capability("interval-assignment")

        :error ->
          add_error(state, :invalid_interval_assignment, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_exercise_statement(state, _kind, "rest-between-sets", raw_value, line_number),
    do:
      put_duration_field(
        state,
        "rest-between-sets",
        raw_value,
        line_number,
        :rest_seconds,
        "rest"
      )

  defp put_exercise_statement(state, _kind, "rest-within-cluster", raw_value, line_number),
    do:
      put_duration_field(
        state,
        "rest-within-cluster",
        raw_value,
        line_number,
        :cluster_rest_seconds,
        "rest"
      )

  defp put_exercise_statement(state, _kind, "rest-after-exercise", raw_value, line_number),
    do:
      put_duration_field(
        state,
        "rest-after-exercise",
        raw_value,
        line_number,
        :rest_pause_seconds,
        "rest"
      )

  defp put_exercise_statement(state, _kind, key, raw_value, line_number)
       when key in [
              "rest-between-reps",
              "rest-between-exercises",
              "rest-between-rounds",
              "rest-between-groups",
              "rest-between-sides",
              "transition-time"
            ] do
    metadata_key =
      case key do
        "transition-time" -> "transition_seconds"
        other -> String.replace(other, "-", "_") <> "_seconds"
      end

    put_parsed_metadata(
      state,
      key,
      raw_value,
      line_number,
      &Values.duration/1,
      :prescription_metadata,
      metadata_key,
      :invalid_duration,
      "rest"
    )
  end

  defp put_exercise_statement(state, _kind, "rest-range", raw_value, line_number) do
    put_parsed_metadata(
      state,
      "rest-range",
      raw_value,
      line_number,
      &Values.duration_range/1,
      :prescription_metadata,
      "rest_range_seconds",
      :invalid_duration_range,
      "rest"
    )
  end

  defp put_exercise_statement(state, _kind, "rest-until", raw_value, line_number) do
    with_text(state, "rest-until", raw_value, line_number, fn text ->
      state
      |> put_top_metadata(:prescription_metadata, "rest_until", text)
      |> mark_capability("rest")
    end)
  end

  defp put_exercise_statement(state, _kind, "target-rpe", raw_value, line_number),
    do:
      put_number_metadata(
        state,
        "target-rpe",
        raw_value,
        line_number,
        "target_rpe",
        [minimum: 0, maximum: 10],
        "target-rpe"
      )

  defp put_exercise_statement(state, _kind, "target-rir", raw_value, line_number),
    do:
      put_parsed_metadata(
        state,
        "target-rir",
        raw_value,
        line_number,
        &Values.integer(&1, minimum: 0),
        :prescription_metadata,
        "target_rir",
        :invalid_integer,
        "target-rir"
      )

  defp put_exercise_statement(state, _kind, "target-heart-rate", raw_value, line_number) do
    bpm = String.replace(raw_value, ~r/\s*bpm$/i, "")

    put_parsed_metadata(
      state,
      "target-heart-rate",
      bpm,
      line_number,
      &Values.integer/1,
      :prescription_metadata,
      "target_heart_rate_bpm",
      :invalid_heart_rate,
      "target-heart-rate"
    )
  end

  defp put_exercise_statement(state, _kind, "cadence", raw_value, line_number) do
    raw_value = String.replace(raw_value, ~r/\s*(rpm|spm)$/i, "")

    put_parsed_metadata(
      state,
      "cadence",
      raw_value,
      line_number,
      &Values.integer/1,
      :prescription_metadata,
      "cadence",
      :invalid_integer,
      "cadence"
    )
  end

  defp put_exercise_statement(state, _kind, "height", raw_value, line_number) do
    raw_value = String.replace(raw_value, ~r/\s*cm$/i, "")

    put_number_metadata(
      state,
      "height",
      raw_value,
      line_number,
      "height_cm",
      [minimum: 0.1],
      "height"
    )
  end

  defp put_exercise_statement(state, _kind, "incline", raw_value, line_number) do
    raw_value = String.replace(raw_value, ~r/\s*%$/i, "")

    put_number_metadata(
      state,
      "incline",
      raw_value,
      line_number,
      "incline_percent",
      [minimum: 0],
      "incline"
    )
  end

  defp put_exercise_statement(state, _kind, "equipment", raw_value, line_number) do
    put_parsed_metadata(
      state,
      "equipment",
      raw_value,
      line_number,
      &Values.list/1,
      :prescription_metadata,
      "equipment",
      :invalid_list,
      "equipment"
    )
  end

  defp put_exercise_statement(state, _kind, key, raw_value, line_number)
       when key in [
              "percentage-of",
              "pace",
              "side",
              "stance",
              "grip",
              "range-of-motion",
              "resistance",
              "score-contribution"
            ] do
    metadata_key = String.replace(key, "-", "_")

    with_text(state, key, raw_value, line_number, fn text ->
      state
      |> put_top_metadata(
        :prescription_metadata,
        metadata_key,
        normalize_metadata_text(key, text)
      )
      |> mark_capability(key)
    end)
  end

  defp put_exercise_statement(state, _kind, "load-mode", raw_value, line_number) do
    mode = raw_value |> String.downcase() |> String.replace("-", "_")

    put_once(state, "load-mode", line_number, fn state ->
      if mode in ~w(absolute pct_1rm bw) do
        state |> put_top_data(:load_mode, mode) |> mark_capability("load")
      else
        add_error(state, :invalid_load_mode, line_number, %{value: raw_value})
      end
    end)
  end

  defp put_exercise_statement(state, kind, "excluded", raw_value, line_number) do
    if kind == :scale do
      put_parsed(
        state,
        "excluded",
        raw_value,
        line_number,
        &Values.boolean/1,
        :excluded,
        :invalid_boolean
      )
    else
      add_error(state, :invalid_parameter_scope, line_number, %{key: "excluded"})
    end
  end

  defp put_exercise_statement(state, _kind, key, _raw_value, line_number) do
    code =
      if Vocabulary.exercise_key?(key),
        do: :unsupported_exercise_parameter,
        else: :unknown_exercise_parameter

    add_error(state, code, line_number, %{key: key})
  end

  defp put_prescription(state, key, raw_value, unit, parser, line_number) do
    put_once(state, key, line_number, fn state ->
      frame = hd(state.frames)

      if Enum.any?(
           ~w(reps duration calories distance),
           &(&1 != key and MapSet.member?(frame.seen, &1))
         ) do
        add_error(state, :conflicting_prescription_dimensions, line_number, %{key: key})
      else
        case parser.(raw_value) do
          {:ok, amount} ->
            state
            |> update_top_data(fn data ->
              data
              |> Map.put(:prescription_value, amount)
              |> Map.put(:prescription_unit, unit)
              |> maybe_put_distance_metadata(unit, amount)
            end)
            |> mark_capability(key)

          :error ->
            add_error(state, :invalid_prescription_value, line_number, %{
              key: key,
              value: raw_value
            })
        end
      end
    end)
  end

  defp put_duration_field(state, key, raw_value, line_number, field, capability) do
    put_parsed(
      state,
      key,
      raw_value,
      line_number,
      &Values.duration/1,
      field,
      :invalid_duration,
      capability
    )
  end

  defp put_number_metadata(state, key, raw_value, line_number, metadata_key, options, capability) do
    put_parsed_metadata(
      state,
      key,
      raw_value,
      line_number,
      &Values.number(&1, options),
      :prescription_metadata,
      metadata_key,
      :invalid_number,
      capability
    )
  end

  defp put_parsed(
         state,
         key,
         raw_value,
         line_number,
         parser,
         field,
         error_code,
         capability \\ nil
       ) do
    put_once(state, key, line_number, fn state ->
      case parser.(raw_value) do
        {:ok, parsed} ->
          state = put_top_data(state, field, parsed)
          if capability, do: mark_capability(state, capability), else: state

        :error ->
          add_error(state, error_code, line_number, %{key: key, value: raw_value})
      end
    end)
  end

  defp put_parsed_metadata(
         state,
         key,
         raw_value,
         line_number,
         parser,
         metadata_field,
         metadata_key,
         error_code,
         capability \\ nil
       ) do
    put_once(state, key, line_number, fn state ->
      case parser.(raw_value) do
        {:ok, parsed} ->
          state = put_top_metadata(state, metadata_field, metadata_key, parsed)
          if capability, do: mark_capability(state, capability), else: state

        :error ->
          add_error(state, error_code, line_number, %{key: key, value: raw_value})
      end
    end)
  end

  defp with_text(state, key, raw_value, line_number, callback) do
    put_once(state, key, line_number, fn state ->
      case text_value(raw_value) do
        {:ok, value} when byte_size(value) <= @max_title_bytes -> callback.(value)
        {:ok, _value} -> add_error(state, :field_too_long, line_number, %{key: key})
        :error -> add_error(state, :invalid_text_value, line_number, %{key: key})
      end
    end)
  end

  defp put_once(state, key, line_number, callback) do
    frame = hd(state.frames)

    if MapSet.member?(frame.seen, key) do
      add_error(state, :duplicate_parameter, line_number, %{key: key})
    else
      state
      |> update_top_frame(&%{&1 | seen: MapSet.put(&1.seen, key)})
      |> callback.()
    end
  end

  defp flush_pending(%{pending: nil} = state), do: state

  defp flush_pending(%{pending: %{kind: :note} = pending} = state) do
    body = pending.lines |> Enum.join("\n") |> String.trim()
    state = %{state | pending: nil}

    cond do
      body == "" ->
        add_error(state, :empty_note, pending.line, %{marker: pending.marker})

      byte_size(body) > @max_note_bytes ->
        add_error(state, :note_too_long, pending.line, %{maximum_bytes: @max_note_bytes})

      true ->
        note_type = String.trim_leading(pending.marker, "!")
        note = %{type: note_type, body: body}

        update_top_data(state, fn data ->
          data = Map.update(data, :notes, [note], &(&1 ++ [note]))
          if note_type == "coach-note", do: data, else: Map.put_new(data, :note, body)
        end)
    end
  end

  defp flush_pending(%{pending: %{kind: :sets} = pending} = state) do
    state = %{state | pending: nil}

    if pending.sets == [] do
      add_error(state, :empty_set_list, pending.line)
    else
      update_top_data(state, fn data ->
        sets =
          pending.sets
          |> Enum.with_index(1)
          |> Enum.map(fn {set, index} -> Map.put(set, :set_index, index) end)

        first = hd(sets)

        data
        |> Map.put(:sets, length(sets))
        |> Map.put(:set_prescriptions, sets)
        |> Map.put(:prescription_value, first.prescription_value)
        |> Map.put(:prescription_unit, first.prescription_unit)
        |> maybe_copy_load(first)
        |> Map.put(:_progression, "explicit")
      end)
    end
  end

  defp finish_document(state, line_number) do
    state =
      cond do
        not state.saw_root -> add_error(state, :missing_workout_block, 1)
        is_nil(state.version) -> add_error(state, :missing_dsl_version, 1)
        true -> state
      end

    Enum.reduce(state.frames, state, fn frame, acc ->
      add_error(acc, :unclosed_block, line_number, %{block: Atom.to_string(frame.kind)})
    end)
  end

  defp finalize_prescriptions(state, data, frame, line_number) do
    progression = value(data, :_progression)
    explicit_sets = value(data, :set_prescriptions, [])
    set_count = value(data, :sets)

    cond do
      progression == "explicit" and explicit_sets == [] ->
        {add_error(state, :explicit_progression_requires_sets, line_number), clean_internal(data)}

      explicit_sets != [] ->
        {state, finalize_explicit_progression(data, explicit_sets)}

      progression == "linear" ->
        finalize_linear_progression(state, data, frame, line_number)

      not is_nil(value(data, :_load_end)) or not is_nil(value(data, :_load_step)) ->
        state = add_error(state, :load_progression_mode_required, line_number)
        {state, clean_internal(data)}

      is_integer(set_count) and set_count > 0 ->
        {state, generate_uniform_sets(data, set_count)}

      not is_nil(value(data, :prescription_value)) or not is_nil(value(data, :_load_exact)) ->
        data = Map.put(data, :sets, 1)
        {state, generate_uniform_sets(data, 1)}

      true ->
        {state, clean_internal(data)}
    end
  end

  defp finalize_explicit_progression(data, explicit_sets) do
    first = hd(explicit_sets)
    values = Enum.map(explicit_sets, &value(&1, :load_value))

    modes =
      explicit_sets |> Enum.map(&value(&1, :load_mode)) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    progression =
      if values |> Enum.reject(&is_nil/1) |> length() > 0 do
        %{
          mode: "per_set",
          direction: infer_direction(values),
          start_value: value(first, :load_value, 0),
          start_mode: value(first, :load_mode, value(data, :load_mode, "absolute")),
          step_value: 0,
          per_set_values: values
        }
      end

    data
    |> Map.put(:sets, length(explicit_sets))
    |> Map.put(:prescription_value, value(first, :prescription_value))
    |> Map.put(:prescription_unit, value(first, :prescription_unit))
    |> maybe_copy_load(first)
    |> maybe_put(:load_progression, if(length(modes) <= 1, do: progression, else: nil))
    |> clean_internal()
  end

  defp finalize_linear_progression(state, data, _frame, line_number) do
    set_count = value(data, :sets)
    start_load = value(data, :_load_start) || load_from_data(data)
    end_load = value(data, :_load_end)
    step_load = value(data, :_load_step)

    cond do
      not is_integer(set_count) or set_count < 1 ->
        {add_error(state, :linear_progression_requires_set_count, line_number),
         clean_internal(data)}

      is_nil(start_load) ->
        {add_error(state, :linear_progression_requires_start_load, line_number),
         clean_internal(data)}

      is_nil(end_load) and is_nil(step_load) ->
        {add_error(state, :linear_progression_requires_end_or_step, line_number),
         clean_internal(data)}

      end_load && (end_load.mode != start_load.mode or end_load.unit != start_load.unit) ->
        {add_error(state, :mixed_progression_load_modes, line_number), clean_internal(data)}

      step_load && (step_load.mode != start_load.mode or step_load.unit != start_load.unit) ->
        {add_error(state, :mixed_progression_load_modes, line_number), clean_internal(data)}

      true ->
        signed_step =
          cond do
            step_load -> step_load.value
            set_count == 1 -> 0
            true -> (end_load.value - start_load.value) / (set_count - 1)
          end

        direction = if signed_step < 0, do: "decrease", else: "increase"
        step_value = abs(signed_step) |> Values.normalize_number()

        sets =
          Enum.map(1..set_count, fn index ->
            load_value =
              (start_load.value + signed_step * (index - 1))
              |> round_precision()

            %{
              set_index: index,
              prescription_value: value(data, :prescription_value),
              prescription_unit: value(data, :prescription_unit),
              load_value: load_value,
              load_mode: start_load.mode,
              note: nil,
              metadata: %{}
            }
          end)

        progression = %{
          mode: "linear",
          direction: direction,
          start_value: start_load.value,
          start_mode: start_load.mode,
          step_value: step_value,
          per_set_values: Enum.map(sets, & &1.load_value)
        }

        finalized =
          data
          |> put_base_load_if_integer(start_load)
          |> put_metadata_value("load_unit", start_load.unit)
          |> Map.put(:set_prescriptions, sets)
          |> Map.put(:load_progression, progression)
          |> clean_internal()

        {state, finalized}
    end
  end

  defp generate_uniform_sets(data, set_count) do
    load = load_from_data(data)

    sets =
      Enum.map(1..set_count, fn index ->
        %{
          set_index: index,
          prescription_value: value(data, :prescription_value),
          prescription_unit: value(data, :prescription_unit),
          load_value: load && load.value,
          load_mode: load && load.mode,
          note: nil,
          metadata: if(load && load.unit, do: %{"load_unit" => load.unit}, else: %{})
        }
      end)

    data
    |> Map.put(:set_prescriptions, sets)
    |> clean_internal()
  end

  defp validate_capabilities(state, frame, line_number) do
    catalog = get_in(frame, [:context, :catalog])

    if catalog do
      Enum.reduce(frame.used, state, fn capability, acc ->
        if ExerciseCatalog.supports?(catalog, capability) do
          acc
        else
          add_error(acc, :exercise_capability_not_supported, line_number, %{
            exercise_ref: catalog.id,
            exercise: catalog.label,
            capability: capability
          })
        end
      end)
    else
      state
    end
  end

  defp validate_section_score(state, frame, line_number) do
    score_config = frame.data.score_config

    cond do
      not frame.data.scoreable or is_nil(score_config) ->
        state

      blank?(value(score_config, :type)) ->
        add_error(state, :missing_score_type, line_number)

      value(score_config, :type) not in Vocabulary.allowed_score_types(
        frame.data.timer_config.type
      ) ->
        add_error(state, :score_not_allowed_for_format, line_number, %{
          score: value(score_config, :type),
          format: frame.data.timer_config.type
        })

      true ->
        state
    end
  end

  defp validate_format_specific_section(
         state,
         %{data: %{timer_config: %{type: "rest"}}} = frame,
         line_number
       ) do
    timer = frame.data.timer_config

    if blank?(value(timer, :duration_seconds)) and blank?(value(timer, :recovery_condition)) do
      add_error(state, :rest_requires_duration_or_recovery_condition, line_number)
    else
      state
    end
  end

  defp validate_format_specific_section(state, _frame, _line_number), do: state

  defp parse_compact_prescription(raw_value) do
    regex =
      ~r/^(\d+)\s*(?:x|×)\s*(\d+)\s*(?:reps?)?(?:\s*@\s*(.+))?$/iu

    case Regex.run(regex, String.trim(raw_value)) do
      [_, raw_sets, raw_reps] ->
        with {:ok, sets} <- Values.integer(raw_sets),
             {:ok, reps} <- Values.integer(raw_reps) do
          {:ok, %{sets: sets, prescription_value: reps, prescription_unit: "reps"}}
        else
          _ -> {:error, :invalid_numbers}
        end

      [_, raw_sets, raw_reps, raw_load] ->
        with {:ok, sets} <- Values.integer(raw_sets),
             {:ok, reps} <- Values.integer(raw_reps),
             {:ok, load} <- Values.load(raw_load) do
          {:ok,
           %{
             sets: sets,
             prescription_value: reps,
             prescription_unit: "reps",
             load_value: load.value,
             load_mode: load.mode,
             prescription_metadata: %{"load_unit" => load.unit}
           }}
        else
          _ -> {:error, :invalid_load_or_numbers}
        end

      _ ->
        {:error, :syntax}
    end
  end

  defp parse_set_line(line) do
    {without_annotation, annotation} =
      extract_annotation(String.trim_leading(line, "-") |> String.trim())

    [base | extras] = String.split(without_annotation, ~r/\s*;\s*/, trim: true)

    with {:ok, prescription} <- parse_set_base(base),
         {:ok, metadata} <- parse_set_metadata(extras, prescription.metadata),
         {:ok, metadata, note} <- apply_set_annotation(metadata, annotation) do
      {:ok, %{prescription | metadata: metadata, note: note}}
    end
  end

  defp parse_set_base(base) do
    regex =
      ~r/^(\d+(?:\.\d+)?)\s*(reps?|sec|secs|seconds?|kcal|m|meters?|km|kilometers?)(?:\s*@\s*(.+))?$/i

    case Regex.run(regex, base) do
      [_, raw_amount, raw_unit] ->
        build_set_prescription(raw_amount, raw_unit, nil)

      [_, raw_amount, raw_unit, raw_load] ->
        build_set_prescription(raw_amount, raw_unit, raw_load)

      _ ->
        {:error, :invalid_base}
    end
  end

  defp build_set_prescription(raw_amount, raw_unit, raw_load) do
    with {:ok, amount, unit} <- parse_set_amount(raw_amount, raw_unit),
         {:ok, load} <- optional_load(raw_load) do
      {:ok,
       %{
         set_index: nil,
         prescription_value: amount,
         prescription_unit: unit,
         load_value: load && load.value,
         load_mode: load && load.mode,
         note: nil,
         metadata: if(load && load.unit, do: %{"load_unit" => load.unit}, else: %{})
       }}
    end
  end

  defp parse_set_amount(raw_amount, raw_unit) do
    unit = String.downcase(raw_unit)

    cond do
      unit in ["rep", "reps", "kcal"] ->
        with {:ok, amount} <- Values.integer(raw_amount) do
          {:ok, amount, if(unit == "kcal", do: "kcal", else: "reps")}
        end

      unit in ["sec", "secs", "second", "seconds"] ->
        with {:ok, amount} <- Values.duration("#{raw_amount} sec") do
          {:ok, amount, "secs"}
        end

      unit in ["m", "meter", "meters", "km", "kilometer", "kilometers"] ->
        with {:ok, amount} <- Values.distance("#{raw_amount} #{unit}") do
          {:ok, amount, "meters"}
        end

      true ->
        {:error, :invalid_unit}
    end
  end

  defp optional_load(nil), do: {:ok, nil}
  defp optional_load(""), do: {:ok, nil}
  defp optional_load(raw_load), do: Values.load(raw_load)

  defp parse_set_metadata([], metadata), do: {:ok, metadata}

  defp parse_set_metadata([entry | rest], metadata) do
    case String.split(entry, ":", parts: 2) do
      [raw_key, raw_value] ->
        key = Vocabulary.canonical_key(raw_key)
        value = String.trim(raw_value)

        case parse_set_metadata_value(key, value) do
          {:ok, metadata_key, parsed} ->
            parse_set_metadata(rest, Map.put(metadata, metadata_key, parsed))

          :error ->
            {:error, {:invalid_set_metadata, key}}
        end

      _ ->
        {:error, :invalid_set_metadata_syntax}
    end
  end

  defp parse_set_metadata_value("tempo", value), do: {:ok, "tempo", value}

  defp parse_set_metadata_value("target-rpe", value) do
    case Values.number(value, minimum: 0, maximum: 10) do
      {:ok, parsed} -> {:ok, "target_rpe", parsed}
      :error -> :error
    end
  end

  defp parse_set_metadata_value("target-rir", value) do
    case Values.integer(value, minimum: 0) do
      {:ok, parsed} -> {:ok, "target_rir", parsed}
      :error -> :error
    end
  end

  defp parse_set_metadata_value("rest-after", value) do
    case Values.duration(value) do
      {:ok, parsed} -> {:ok, "rest_after_seconds", parsed}
      :error -> :error
    end
  end

  defp parse_set_metadata_value("side", value) do
    normalized = String.downcase(value)

    if normalized in ~w(left right both each alternating),
      do: {:ok, "side", normalized},
      else: :error
  end

  defp parse_set_metadata_value(_key, _value), do: :error

  defp apply_set_annotation(metadata, nil), do: {:ok, metadata, nil}

  defp apply_set_annotation(metadata, annotation) do
    if String.downcase(annotation) == "deload" do
      {:ok, Map.put(metadata, "deload", true), "deload"}
    else
      {:ok, metadata, annotation}
    end
  end

  defp extract_annotation(value) do
    case Regex.run(~r/^(.*?)(?:\s*\[([^\]]+)\])?$/, value) do
      [_, base] -> {String.trim(base), nil}
      [_, base, annotation] -> {String.trim(base), String.trim(annotation)}
    end
  end

  defp text_value(raw_value) when is_binary(raw_value) do
    value = String.trim(raw_value)

    cond do
      value == "" ->
        :error

      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        inner = String.slice(value, 1, max(String.length(value) - 2, 0))

        decoded =
          inner
          |> String.replace("\\n", "\n")
          |> String.replace("\\\"", "\"")
          |> String.replace("\\\\", "\\")

        if safe_text?(decoded), do: {:ok, decoded}, else: :error

      String.starts_with?(value, "\"") or String.ends_with?(value, "\"") ->
        :error

      safe_text?(value) ->
        {:ok, value}

      true ->
        :error
    end
  end

  defp safe_text?(value) do
    not String.contains?(value, <<0>>) and String.valid?(value)
  end

  defp structural_statement?(line) do
    line == "" or String.starts_with?(line, "[") or String.starts_with?(line, "!") or
      Regex.match?(~r/^[a-z][a-z0-9_-]*:\s*/iu, line)
  end

  defp base_exercise(name, exercise_ref) do
    %{
      item_type: "exercise",
      name: name,
      exercise_ref: exercise_ref,
      variations: [],
      notes: [],
      prescription_metadata: %{},
      set_prescriptions: []
    }
  end

  defp frame(kind, line, data, context \\ %{}) do
    %{
      kind: kind,
      line: line,
      data: data,
      seen: MapSet.new(),
      used: MapSet.new(),
      context: context
    }
  end

  defp current_kind(%{frames: [frame | _]}), do: frame.kind
  defp current_kind(_state), do: nil

  defp update_top_frame(%{frames: [frame | rest]} = state, callback),
    do: %{state | frames: [callback.(frame) | rest]}

  defp update_top_data(state, callback),
    do: update_top_frame(state, &%{&1 | data: callback.(&1.data)})

  defp put_top_data(state, field, value),
    do: update_top_data(state, &Map.put(&1, field, value))

  defp put_top_metadata(state, field, key, value) do
    update_top_data(state, fn data ->
      Map.update(data, field, %{key => value}, &Map.put(&1, key, value))
    end)
  end

  defp mark_capability(state, capability) do
    update_top_frame(state, &%{&1 | used: MapSet.put(&1.used, capability)})
  end

  defp add_error(state, code, line, params \\ %{}),
    do: add_diagnostic(state, code, :error, line, params)

  defp add_warning(state, code, line, params),
    do: add_diagnostic(state, code, :warning, line, params)

  defp add_diagnostic(state, code, severity, line, params) do
    update_in(state.diagnostics, &[diagnostic(code, line, params, severity) | &1])
  end

  defp diagnostic(code, line, params \\ %{}, severity \\ :error) do
    %{code: code, severity: severity, line: max(line, 1), column: 1, params: params}
  end

  defp require_frame_value(state, frame, key, code, line_number) do
    if blank?(value(frame.data, key)),
      do: add_error(state, code, line_number),
      else: state
  end

  defp assign_order(items) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, order} -> Map.put(item, :order, order) end)
  end

  defp inherit_group_sets(item, nil), do: item
  defp inherit_group_sets(%{sets: sets} = item, _group_sets) when not is_nil(sets), do: item
  defp inherit_group_sets(item, group_sets), do: Map.put(item, :sets, group_sets)

  defp put_load(data, load) do
    data
    |> Map.put(:_load_exact, load)
    |> put_base_load_if_integer(load)
    |> put_metadata_value("load_unit", load.unit)
  end

  defp apply_compact_fields(data, fields) do
    load =
      case Map.get(fields, :load_value) do
        nil ->
          nil

        load_value ->
          %{
            value: load_value,
            mode: Map.get(fields, :load_mode),
            unit: fields |> Map.get(:prescription_metadata, %{}) |> value("load_unit")
          }
      end

    data =
      fields
      |> Map.drop([:load_value, :load_mode])
      |> then(&Map.merge(data, &1))

    if load, do: put_load(data, load), else: data
  end

  defp load_from_data(data) do
    case value(data, :_load_exact) do
      %{value: _value} = load ->
        load

      _ ->
        load_from_base_data(data)
    end
  end

  defp load_from_base_data(data) do
    case value(data, :load_value) do
      nil ->
        nil

      load_value ->
        %{
          value: load_value,
          mode: value(data, :load_mode, "absolute"),
          unit: data |> value(:prescription_metadata, %{}) |> value("load_unit", "kg")
        }
    end
  end

  defp put_metadata_value(data, key, value) do
    Map.update(data, :prescription_metadata, %{key => value}, &Map.put(&1, key, value))
  end

  defp maybe_put_distance_metadata(data, "meters", amount),
    do: put_metadata_value(data, "distance_meters", amount)

  defp maybe_put_distance_metadata(data, _unit, _amount), do: data

  defp maybe_copy_load(data, prescription) do
    case value(prescription, :load_value) do
      nil ->
        data

      load_value ->
        metadata = value(prescription, :metadata, %{})

        data
        |> Map.update(:prescription_metadata, metadata, &Map.merge(&1, metadata))
        |> put_base_load_if_integer(%{
          value: load_value,
          mode: value(prescription, :load_mode),
          unit: value(metadata, "load_unit")
        })
    end
  end

  defp infer_direction(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value("increase", fn
      [left, right] when right > left -> "increase"
      [left, right] when right < left -> "decrease"
      _ -> nil
    end)
  end

  defp clean_internal(data) do
    Map.drop(data, [:_progression, :_load_start, :_load_end, :_load_step, :_load_exact])
  end

  defp put_base_load_if_integer(data, %{value: value, mode: mode}) when is_integer(value) do
    data
    |> Map.put(:load_value, value)
    |> Map.put(:load_mode, mode)
  end

  defp put_base_load_if_integer(data, _load),
    do: Map.drop(data, [:load_value, :load_mode])

  defp group_identity(item),
    do: value(item, :superset_group_id) || value(item, :alternating_group_id)

  defp deterministic_uuid(value) do
    <<a::32, b::16, c::16, d::16, e::48, _rest::binary>> = :crypto.hash(:sha256, value)
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x5000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    Enum.join(
      [
        hex(a, 8),
        hex(b, 4),
        hex(c, 4),
        hex(d, 4),
        hex(e, 12)
      ],
      "-"
    )
  end

  defp hex(value, width),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")

  defp normalize_score_type(raw_value) do
    case raw_value |> String.downcase() |> String.replace("-", "_") do
      "rounds_and_reps" -> "rounds+reps"
      "completed_reps" -> "reps"
      value -> value
    end
  end

  defp normalize_metadata_text("side", value), do: String.downcase(value)
  defp normalize_metadata_text(_key, value), do: value

  defp maybe_mark_load(state, fields) do
    if Map.has_key?(fields, :load_value), do: mark_capability(state, "load"), else: state
  end

  defp elem_or({:ok, value}, _fallback), do: value
  defp elem_or(:error, fallback), do: fallback

  defp value(map, key, default \\ nil)
  defp value(nil, _key, default), do: default

  defp value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp reject_nil_values(map),
    do: Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)

  defp round_precision(number) when is_float(number),
    do: number |> Float.round(4) |> Values.normalize_number()

  defp round_precision(number), do: number

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?([]), do: true
  defp blank?(_value), do: false
end
