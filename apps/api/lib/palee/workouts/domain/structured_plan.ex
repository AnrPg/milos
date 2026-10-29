defmodule Palee.Workouts.Domain.StructuredPlan do
  @moduledoc """
  One section of a workout written in the structured WOD editor (ADR-270), pure.

  A plan is the web contract `PlanSection` (`apps/web/src/lib/structured-plan/types.ts`):
  a map with camelCase string keys, `v: 1`, kept in `workout_sections.plan`.
  Three levels never mix: the section's `flow` (how the clock runs), the
  `structs` of one set or round (per row or group), and the `mods` add-ons.
  Every value is the text the coach typed; `validate/1` re-reads it with the
  editor's rules (`StructuredPlan.Notation`, the same rules as the web
  `validate.ts`) and refuses what does not read:

  * a known `flow`, `v` = 1, and the flow's `params` read as their kind
    (count, sets range, time, AMRAP windows);
  * structures only where the flow allows them, add-ons likewise;
  * known measures, tempo in four marks (digits or X), RPE at most 10;
  * the load unit (kg or %) once per row: a row of bare numbers with no unit
    anywhere, or a row mixing kg and %, is refused; words are fine;
  * bounds: at most 12 blocks, 60 rows per block, 30 cells per row, strings
    of 200 characters and notes of 2000.

  Errors are `%{path: "blocks.0.1.cells.2.l", code: "missing_unit"}`: the
  JSON path inside the plan, segments joined by dots.
  """

  alias Palee.Workouts.Domain.StructuredPlan.Notation

  @version 1
  @max_blocks 12
  @max_rows 60
  @max_cells 30
  @max_string 200
  @max_note 2000
  @max_exercise_ref 120
  @max_level_notes 20

  # Level 1: each flow's params (key => kind), structures and add-ons.
  @flows %{
    "sets" => %{
      params: %{"sets" => :range, "rest" => :time},
      structs: ~w(single superset complex cluster drop restpause),
      mods: ~w(interrupt)
    },
    "for_time" => %{
      params: %{"rounds" => :count, "cap" => :time_min},
      structs: ~w(single superset complex),
      mods: ~w(interrupt)
    },
    "amrap" => %{
      params: %{"dur" => :times, "rest" => :time},
      structs: ~w(single superset complex),
      mods: ~w(interrupt)
    },
    "emom" => %{
      params: %{"every" => :time, "times" => :count},
      structs: ~w(single superset complex cluster),
      mods: []
    },
    "intervals" => %{
      params: %{"work" => :time, "off" => :time, "rounds" => :count},
      structs: ~w(single superset complex),
      mods: ~w(hr)
    },
    "rest" => %{params: %{"dur" => :time_min}, structs: [], mods: []}
  }
  @mod_params %{"interrupt" => {"intEvery", :time}, "hr" => {"hrTarget", :count}}
  @param_keys ~w(sets rest rounds cap dur every times work off intEvery hrTarget)

  # Level 2: the fields of each structure.
  @structs %{
    "single" => %{},
    "superset" => %{},
    "complex" => %{},
    "cluster" => %{"clusters" => :count, "intra" => :time},
    "drop" => %{"drops" => :count, "dropby" => :text},
    "restpause" => %{"minis" => :count, "intra" => :time}
  }

  @measures ~w(pace tempo rpe rir zone height dist hold side)
  @cell_keys ["d", "l" | @measures -- ["side"]]
  @row_keys ~w(id kind name exerciseRef dose load x extra cells perRound group note)
  @section_keys ~w(v flow preset params mods blocks interrupt structs score note levelNotes)

  @type error :: %{path: String.t(), code: String.t()}

  def version, do: @version
  def flows, do: @flows |> Map.keys() |> Enum.sort()
  def measures, do: @measures
  def max_blocks, do: @max_blocks
  def max_rows, do: @max_rows
  def max_cells, do: @max_cells

  @doc "`:ok`, or `{:error, errors}` listing every problem with its path."
  @spec validate(term()) :: :ok | {:error, [error()]}
  def validate(plan) do
    case errors(plan) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  The plan as it is kept: validated, with keys outside the contract left out
  (so the column holds only the contract), or `{:error, errors}`.
  """
  @spec normalize(term()) :: {:ok, map()} | {:error, [error()]}
  def normalize(plan) do
    with :ok <- validate(plan) do
      {:ok, clean(plan)}
    end
  end

  @doc "Every problem of a plan, in document order."
  @spec errors(term()) :: [error()]
  def errors(%{} = plan) do
    flow = Map.get(plan, "flow")

    if Map.has_key?(@flows, flow) do
      spec = Map.fetch!(@flows, flow)

      Enum.concat([
        version_errors(plan),
        params_errors(plan, spec),
        mods_errors(plan, spec),
        blocks_errors(plan),
        interrupt_errors(plan),
        structs_errors(plan, spec),
        string_errors(plan, "score", @max_string, ["score"], required: true),
        string_errors(plan, "preset", @max_string, ["preset"], nullable: true),
        string_errors(plan, "note", @max_note, ["note"]),
        level_notes_errors(plan)
      ])
    else
      version_errors(plan) ++ [error(["flow"], "unknown_flow")]
    end
  end

  def errors(_plan), do: [error([], "invalid")]

  @doc "Exercise rows of a plan in order: every block's rows, then the interruption's."
  @spec rows(map()) :: [map()]
  def rows(%{} = plan) do
    blocks =
      case Map.get(plan, "blocks") do
        blocks when is_list(blocks) -> Enum.flat_map(blocks, &List.wrap/1)
        _none -> []
      end

    interrupt =
      case Map.get(plan, "interrupt") do
        rows when is_list(rows) -> rows
        _none -> []
      end

    Enum.filter(blocks ++ interrupt, &is_map/1)
  end

  def rows(_plan), do: []

  @doc "Execution units of a list of rows: one row, or consecutive rows of one group."
  @spec units([map()]) :: [%{group: String.t() | nil, rows: [map()]}]
  def units(rows) do
    rows
    |> Enum.reduce([], fn row, acc ->
      group = Map.get(row, "group")

      case acc do
        [%{group: ^group} = last | rest] when is_binary(group) and group != "" ->
          [%{last | rows: last.rows ++ [row]} | rest]

        _other ->
          [%{group: blank_to_nil(group), rows: [row]} | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc "How many exercise rows the plan's blocks hold (for summaries)."
  @spec exercise_count(term()) :: non_neg_integer()
  def exercise_count(%{} = plan) do
    case Map.get(plan, "blocks") do
      blocks when is_list(blocks) ->
        blocks
        |> Enum.flat_map(&List.wrap/1)
        |> Enum.count(&(is_map(&1) and Map.get(&1, "kind") == "ex"))

      _none ->
        0
    end
  end

  def exercise_count(_plan), do: 0

  # ── section ──────────────────────────────────────────

  defp version_errors(plan) do
    if Map.get(plan, "v") == @version, do: [], else: [error(["v"], "unsupported_version")]
  end

  defp params_errors(plan, spec) do
    case Map.get(plan, "params") do
      %{} = params ->
        mods = active_mods(plan)

        allowed =
          Enum.reduce(mods, spec.params, fn mod, acc ->
            case Map.fetch(@mod_params, mod) do
              {:ok, {key, kind}} -> Map.put(acc, key, kind)
              :error -> acc
            end
          end)

        params
        |> Enum.sort()
        |> Enum.flat_map(fn {key, value} -> param_errors(key, value, allowed) end)

      _other ->
        [error(["params"], "invalid")]
    end
  end

  # Keys of another flow (kept while the coach switches flows) are left alone.
  defp param_errors(key, value, allowed) do
    path = ["params", key]

    cond do
      key not in @param_keys -> [error(path, "unknown_param")]
      not is_binary(value) -> [error(path, "invalid")]
      String.length(value) > @max_string -> [error(path, "too_long")]
      Map.has_key?(allowed, key) -> param_value_errors(Map.fetch!(allowed, key), value, path)
      true -> []
    end
  end

  defp param_value_errors(kind, value, path) do
    if value_reads?(kind, value), do: [], else: [error(path, "bad_param")]
  end

  defp value_reads?(kind, value) do
    if String.trim(value) == "", do: true, else: reads?(kind, value)
  end

  defp reads?(:count, value), do: Notation.count?(value)
  defp reads?(:range, value), do: Notation.count_range?(value)
  defp reads?(:time, value), do: Notation.parse_clock(value, :smart) != :bad
  defp reads?(:time_min, value), do: Notation.parse_clock(value, :min) != :bad
  defp reads?(:times, value), do: Notation.parse_times(value) != :bad
  defp reads?(:text, _value), do: true

  defp active_mods(plan) do
    case Map.get(plan, "mods") do
      %{} = mods -> for {mod, true} <- mods, do: mod
      _none -> []
    end
  end

  defp mods_errors(plan, spec) do
    case Map.get(plan, "mods") do
      nil ->
        []

      %{} = mods ->
        mods
        |> Enum.sort()
        |> Enum.flat_map(fn {mod, on} ->
          cond do
            not Map.has_key?(@mod_params, mod) -> [error(["mods", mod], "unknown_mod")]
            not is_boolean(on) -> [error(["mods", mod], "invalid")]
            on and mod not in spec.mods -> [error(["mods", mod], "mod_not_allowed")]
            true -> []
          end
        end)

      _other ->
        [error(["mods"], "invalid")]
    end
  end

  defp blocks_errors(plan) do
    case Map.get(plan, "blocks") do
      blocks when is_list(blocks) and length(blocks) > @max_blocks ->
        [error(["blocks"], "too_many_blocks")]

      blocks when is_list(blocks) ->
        blocks
        |> Enum.with_index()
        |> Enum.flat_map(fn {block, index} -> rows_errors(block, ["blocks", index]) end)

      _other ->
        [error(["blocks"], "invalid")]
    end
  end

  defp interrupt_errors(plan) do
    case Map.get(plan, "interrupt") do
      nil -> []
      rows -> rows_errors(rows, ["interrupt"])
    end
  end

  defp rows_errors(rows, path) when is_list(rows) and length(rows) > @max_rows,
    do: [error(path, "too_many_rows")]

  defp rows_errors(rows, path) when is_list(rows) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, index} -> row_errors(row, path ++ [index]) end)
  end

  defp rows_errors(_rows, path), do: [error(path, "invalid")]

  defp structs_errors(plan, spec) do
    case Map.get(plan, "structs") do
      nil ->
        []

      %{} = structs ->
        structs
        |> Enum.sort()
        |> Enum.flat_map(fn {key, struct} -> struct_errors(key, struct, spec) end)

      _other ->
        [error(["structs"], "invalid")]
    end
  end

  defp struct_errors(key, %{} = struct, spec) do
    path = ["structs", key]
    kind = Map.get(struct, "kind")

    cond do
      String.length(key) > @max_string ->
        [error(path, "too_long")]

      not Map.has_key?(@structs, kind) ->
        [error(path ++ ["kind"], "unknown_struct")]

      kind not in spec.structs ->
        [error(path ++ ["kind"], "struct_not_allowed")]

      true ->
        @structs
        |> Map.fetch!(kind)
        |> Enum.sort()
        |> Enum.flat_map(fn {field, field_kind} ->
          struct_field_errors(Map.get(struct, field), field_kind, path ++ [field])
        end)
    end
  end

  defp struct_errors(key, _struct, _spec), do: [error(["structs", key], "invalid")]

  defp struct_field_errors(nil, _kind, _path), do: []

  defp struct_field_errors(value, _kind, path) when not is_binary(value),
    do: [error(path, "invalid")]

  defp struct_field_errors(value, kind, path) do
    cond do
      String.length(value) > @max_string -> [error(path, "too_long")]
      value_reads?(kind, value) -> []
      true -> [error(path, "bad_param")]
    end
  end

  defp level_notes_errors(plan) do
    case Map.get(plan, "levelNotes") do
      nil ->
        []

      %{} = notes when map_size(notes) > @max_level_notes ->
        [error(["levelNotes"], "too_many_level_notes")]

      %{} = notes ->
        notes
        |> Enum.sort()
        |> Enum.flat_map(fn {level, _note} ->
          if String.length(level) > @max_string,
            do: [error(["levelNotes", level], "too_long")],
            else: string_errors(notes, level, @max_note, ["levelNotes", level])
        end)

      _other ->
        [error(["levelNotes"], "invalid")]
    end
  end

  # ── rows ─────────────────────────────────────────────

  defp row_errors(%{} = row, path) do
    kind = Map.get(row, "kind")

    Enum.concat([
      row_id_errors(row, path),
      if(kind in ["ex", "rest"], do: [], else: [error(path ++ ["kind"], "invalid")]),
      string_errors(row, "name", @max_string, path ++ ["name"]),
      string_errors(row, "exerciseRef", @max_exercise_ref, path ++ ["exerciseRef"],
        nullable: true
      ),
      string_errors(row, "group", @max_string, path ++ ["group"], nullable: true),
      string_errors(row, "note", @max_note, path ++ ["note"]),
      boolean_errors(row, "perRound", path),
      extra_errors(row, path),
      dose_errors(Map.get(row, "dose"), path ++ ["dose"]),
      compact_load_errors(Map.get(row, "load"), path ++ ["load"]),
      x_errors(row, path),
      cells_errors(row, path)
    ])
  end

  defp row_errors(_row, path), do: [error(path, "invalid")]

  defp row_id_errors(row, path) do
    case Map.get(row, "id") do
      id when is_binary(id) and id != "" ->
        if String.length(id) > @max_string, do: [error(path ++ ["id"], "too_long")], else: []

      _other ->
        [error(path ++ ["id"], "required")]
    end
  end

  defp boolean_errors(row, key, path) do
    if Map.get(row, key) in [nil, true, false], do: [], else: [error(path ++ [key], "invalid")]
  end

  defp extra_errors(row, path) do
    case Map.get(row, "extra") do
      nil ->
        []

      extra when is_list(extra) ->
        extra
        |> Enum.with_index()
        |> Enum.flat_map(fn {measure, index} ->
          if measure in @measures,
            do: [],
            else: [error(path ++ ["extra", index], "unknown_measure")]
        end)

      _other ->
        [error(path ++ ["extra"], "invalid")]
    end
  end

  defp x_errors(row, path) do
    case Map.get(row, "x") do
      nil ->
        []

      %{} = values ->
        values
        |> Enum.sort()
        |> Enum.flat_map(fn {key, value} ->
          measure_errors(key, value, path ++ ["x", key], :compact)
        end)

      _other ->
        [error(path ++ ["x"], "invalid")]
    end
  end

  defp cells_errors(row, path) do
    case Map.get(row, "cells") do
      nil ->
        []

      cells when is_list(cells) and length(cells) > @max_cells ->
        [error(path ++ ["cells"], "too_many_cells")]

      cells when is_list(cells) ->
        cell_errors =
          cells
          |> Enum.with_index()
          |> Enum.flat_map(fn {cell, index} -> cell_errors(cell, path ++ ["cells", index]) end)

        cell_errors ++ row_load_errors(cells, path)

      _other ->
        [error(path ++ ["cells"], "invalid")]
    end
  end

  defp cell_errors(nil, _path), do: []

  defp cell_errors(%{} = cell, path) do
    cell
    |> Enum.sort()
    |> Enum.flat_map(fn
      {"d", value} -> cell_dose_errors(value, path ++ ["d"])
      {"l", value} -> string_errors(%{"l" => value}, "l", @max_string, path ++ ["l"])
      {key, value} -> measure_errors(key, value, path ++ [key], :cell)
    end)
  end

  defp cell_errors(_cell, path), do: [error(path, "invalid")]

  # The unit is written once per row: bare numbers take the unit another
  # column states; none anywhere, or kg mixed with %, is refused.
  defp row_load_errors(cells, path) do
    loads =
      Enum.map(cells, fn
        %{"l" => load} when is_binary(load) -> load
        _cell -> nil
      end)

    %{issues: issues} = Notation.row_load_issues(loads)

    issues
    |> Enum.sort()
    |> Enum.map(fn {index, issue} ->
      error(path ++ ["cells", index, "l"], Atom.to_string(issue))
    end)
  end

  defp dose_errors(nil, _path), do: []
  defp dose_errors(value, path) when not is_binary(value), do: [error(path, "invalid")]

  defp dose_errors(value, path) do
    cond do
      String.length(value) > @max_string -> [error(path, "too_long")]
      Notation.parse_dose(value) == :bad -> [error(path, "bad_dose")]
      true -> []
    end
  end

  # A cell may also change by x from the column before, or spread to the last.
  defp cell_dose_errors(value, path) when is_binary(value) do
    if Notation.relative?(value) and String.length(value) <= @max_string,
      do: [],
      else: dose_errors(value, path)
  end

  defp cell_dose_errors(value, path), do: dose_errors(value, path)

  # The same-for-every-set load: a bare number has no unit to inherit.
  defp compact_load_errors(nil, _path), do: []
  defp compact_load_errors(value, path) when not is_binary(value), do: [error(path, "invalid")]

  defp compact_load_errors(value, path) do
    cond do
      String.length(value) > @max_string -> [error(path, "too_long")]
      Regex.match?(~r/^\d+(?:[.,]\d+)?$/, String.trim(value)) -> [error(path, "missing_unit")]
      true -> []
    end
  end

  defp measure_errors(key, value, path, place) do
    cond do
      key not in @cell_keys or key in ["d", "l"] -> [error(path, "unknown_measure")]
      not is_binary(value) -> [error(path, "invalid")]
      String.length(value) > @max_string -> [error(path, "too_long")]
      String.trim(value) == "" -> []
      key == "tempo" -> if Notation.tempo?(value), do: [], else: [error(path, "bad_tempo")]
      not numeric?(value, place) -> [error(path, "bad_number")]
      key == "rpe" and rpe_over_max?(value) -> [error(path, "rpe_max")]
      true -> []
    end
  end

  defp numeric?(value, :cell), do: Regex.match?(~r/^[+-]?\d/, String.trim(value))
  defp numeric?(value, :compact), do: Regex.match?(~r/^\d/, String.trim(value))

  # RPE is out of 10: a stated value (or a spread's end) above 10 is refused.
  defp rpe_over_max?(value) do
    value = String.trim(value)

    if Regex.match?(~r/^[+-]/, value) do
      false
    else
      ~r/\d+(?:[.,]\d+)?/
      |> Regex.scan(value)
      |> Enum.any?(fn [number] -> number |> String.replace(",", ".") |> parse_number() > 10 end)
    end
  end

  defp parse_number(text) do
    case Float.parse(text) do
      {number, _rest} -> number
      :error -> 0
    end
  end

  # ── helpers ──────────────────────────────────────────

  defp string_errors(map, key, max, path, opts \\ []) do
    case Map.get(map, key) do
      nil ->
        if Keyword.get(opts, :required, false), do: [error(path, "required")], else: []

      value when is_binary(value) ->
        if String.length(value) > max, do: [error(path, "too_long")], else: []

      _other ->
        [error(path, "invalid")]
    end
  end

  defp error(path, code), do: %{path: Enum.map_join(path, ".", &to_string/1), code: code}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # ── clean ────────────────────────────────────────────

  defp clean(plan) do
    plan
    |> Map.take(@section_keys)
    |> Map.update!("blocks", fn blocks -> Enum.map(blocks, &clean_rows/1) end)
    |> update_present("interrupt", &clean_rows/1)
  end

  defp clean_rows(rows), do: Enum.map(rows, &Map.take(&1, @row_keys))

  defp update_present(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, nil} -> map
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end
end
