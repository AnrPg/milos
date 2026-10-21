defmodule Palee.Repo.Migrations.WorkoutContent do
  @moduledoc """
  ADR-140 §4 (M5.5): workout notes become workout content.

  * `notes` columns become `content`, and every stored entry gets its
    canonical type: `note` / `athlete-note` become `instructions` (Οδηγίες)
    on a workout, section, group or header and `cue` on an exercise or a
    scale variation; `coach-note` becomes `coach-brief`; `scaling-note`,
    `safety-note` and `equipment-note` drop their suffix.
  * The same rewrite runs over the DSL source text, the parsed DSL document
    and the structured draft, so every copy of a workout reads the same.
  * An assignment's `admin_notes` become its `instructions`.

  The migration is self-contained: it does not call application code.
  """

  use Ecto.Migration

  @fixed %{
    "coach-note" => "coach-brief",
    "scaling-note" => "scaling",
    "safety-note" => "safety",
    "equipment-note" => "equipment"
  }

  def up do
    for table <- ~w(master_workouts workout_sections workout_exercises exercise_variations)a do
      rename table(table), :notes, to: :content
    end

    rename table(:assigned_workouts), :admin_notes, to: :instructions

    flush()

    retype("master_workouts", "'instructions'")
    retype("workout_sections", "'instructions'")

    retype(
      "workout_exercises",
      "CASE WHEN item_type = 'header' THEN 'instructions' ELSE 'cue' END"
    )

    retype("exercise_variations", "'cue'")

    execute("""
    UPDATE workout_exercises
    SET group_config = (group_config - 'notes') ||
      jsonb_build_object('content', #{retyped_json("group_config->'notes'", "'instructions'")})
    WHERE group_config ? 'notes'
    """)

    rewrite_workout_documents()
  end

  def down do
    raise Ecto.MigrationError,
      message: "workout content cannot be turned back into untyped notes"
  end

  # `content` is jsonb[]: rewrite each entry's type, keeping the order.
  defp retype(table, primary) do
    execute("""
    UPDATE #{table}
    SET content = ARRAY(
      SELECT jsonb_set(entry, '{type}', to_jsonb(#{type_case("entry->>'type'", primary)}))
      FROM unnest(content) WITH ORDINALITY AS item(entry, position)
      ORDER BY position
    )
    WHERE cardinality(content) > 0
    """)
  end

  defp retyped_json(source, primary) do
    """
    COALESCE((
      SELECT jsonb_agg(
        jsonb_set(entry, '{type}', to_jsonb(#{type_case("entry->>'type'", primary)}))
        ORDER BY position
      )
      FROM jsonb_array_elements(#{source}) WITH ORDINALITY AS item(entry, position)
    ), '[]'::jsonb)
    """
  end

  defp type_case(type, primary) do
    fixed = Enum.map_join(@fixed, " ", fn {from, to} -> "WHEN '#{from}' THEN '#{to}'" end)

    "(CASE #{type} WHEN 'note' THEN #{primary} WHEN 'athlete-note' THEN #{primary} #{fixed} ELSE #{type} END)"
  end

  defp rewrite_workout_documents do
    %{rows: rows} =
      repo().query!("""
      SELECT id, dsl_source, dsl_document, draft_data
      FROM master_workouts
      WHERE dsl_source IS NOT NULL OR dsl_document IS NOT NULL OR draft_data IS NOT NULL
      """)

    Enum.each(rows, fn [id, source, document, draft] ->
      repo().query!(
        "UPDATE master_workouts SET dsl_source = $2, dsl_document = $3, draft_data = $4 WHERE id = $1",
        [id, rewrite_source(source), walk(document, :workout), walk(draft, :workout)]
      )
    end)
  end

  # DSL text: a marker's level is the innermost open block.
  defp rewrite_source(nil), do: nil

  defp rewrite_source(source) do
    {lines, _stack} =
      source
      |> String.split("\n")
      |> Enum.map_reduce([:workout], fn line, stack ->
        trimmed = String.trim(line)

        cond do
          match = Regex.run(~r/^\[(workout|section|group|exercise|header|scale)\b/i, trimmed) ->
            {line, [block_level(Enum.at(match, 1)) | stack]}

          Regex.match?(~r/^\[\/(workout|section|group|exercise|header|scale)\]$/i, trimmed) ->
            {line, tl_or_root(stack)}

          match = Regex.run(~r/^!([a-z][a-z-]*):\s*$/i, trimmed) ->
            type = match |> Enum.at(1) |> String.downcase() |> canonical(hd(stack))
            {String.replace(line, ~r/![a-z][a-z-]*:/i, "!#{type}:", global: false), stack}

          true ->
            {line, stack}
        end
      end)

    Enum.join(lines, "\n")
  end

  defp block_level(block) do
    case String.downcase(block) do
      "scale" -> :variation
      other -> String.to_atom(other)
    end
  end

  defp tl_or_root([_level]), do: [:workout]
  defp tl_or_root([_level | rest]), do: rest

  # Parsed DSL documents and structured drafts share one shape.
  defp walk(nil, _level), do: nil

  defp walk(%{} = map, level) do
    map
    |> rename_notes(level)
    |> update_list("sections", &walk(&1, :section))
    |> update_list("exercises", &walk(&1, item_level(&1)))
    |> update_list("items", &walk(&1, item_level(&1)))
    |> update_list("variations", &walk(&1, :variation))
    |> update_map("group_config", &rename_notes(&1, :group))
  end

  defp walk(other, _level), do: other

  defp item_level(%{"item_type" => "header"}), do: :header
  defp item_level(_item), do: :exercise

  defp rename_notes(%{"notes" => notes} = map, level) when is_list(notes) do
    content = Enum.map(notes, &retype_entry(&1, level))
    map |> Map.delete("notes") |> Map.put("content", content)
  end

  defp rename_notes(map, _level), do: map

  defp retype_entry(%{"type" => type} = entry, level),
    do: Map.put(entry, "type", canonical(type, level))

  defp retype_entry(entry, _level), do: entry

  defp canonical(type, level) when type in ["note", "athlete-note", "instructions"],
    do: if(level in [:exercise, :variation], do: "cue", else: "instructions")

  defp canonical(type, _level), do: Map.get(@fixed, type, type)

  defp update_list(map, key, fun) do
    case map do
      %{^key => list} when is_list(list) -> Map.put(map, key, Enum.map(list, fun))
      _other -> map
    end
  end

  defp update_map(map, key, fun) do
    case map do
      %{^key => %{} = value} -> Map.put(map, key, fun.(value))
      _other -> map
    end
  end
end
