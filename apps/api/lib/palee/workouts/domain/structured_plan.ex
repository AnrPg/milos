defmodule Palee.Workouts.Domain.StructuredPlan do
  @moduledoc """
  One section of a workout written in the structured WOD editor (ADR-270), pure.

  A plan is the web contract `PlanSection` (`apps/web/src/lib/structured-plan/types.ts`):
  a map with camelCase string keys, `v: 1`, kept in `workout_sections.plan`.
  Three levels never mix: the section's `flow` (how the clock runs), the
  `structs` of one set or round (per row or group), and the `mods` add-ons.
  Every value is the text the coach typed; `validate/1` re-reads it with the
  editor's rules and returns the same codes at the same paths as the web
  `validateSection` (`apps/web/src/lib/structured-plan/validate.ts`):

  * `bad_version`, `unknown_flow`; `mod_not_allowed`; params read per kind
    (`bad_param`; `unknown_param` for a non-empty key the flow never has);
    `unknown_score` (the flow's scores, plus its preset's);
  * rows: `bad_row_kind`, `duplicate_id`, `unknown_measure`,
    `duplicate_measure`; values per column (the sets grid, or per round)
    or the same-every-time values: `bad_dose`, `missing_unit` /
    `mixed_unit` (the load unit is written once per row), `bad_tempo`,
    `bad_measure_value`, `rpe_over_max`;
  * structures: `unknown_struct`, `struct_not_allowed`, `bad_struct_param`;
  * bounds: `blocks_not_allowed` (a rest section), `too_many_blocks` (12),
    `too_many_rows` (60), `too_many_cells` (30), `too_long` (200),
    `note_too_long` (2000).

  The API also refuses what the editor cannot produce (a value of the wrong
  JSON type, a row without an id) with `invalid`.

  Errors are `%{path: "blocks.0.1.cells.2.l", code: "missing_unit"}`: dot
  separated keys and indexes from the section root.
  """

  alias Palee.Workouts.Domain.StructuredPlan.{Catalog, Notation}

  @version 1
  @max_blocks 12
  @max_rows 60
  @max_cells 30
  @max_text 200
  @max_note 2000
  @max_level_notes 20

  @row_keys ~w(id kind name exerciseRef dose load x extra cells perRound group note)
  @section_keys ~w(v flow preset params mods blocks interrupt structs score note levelNotes)

  @type error :: %{path: String.t(), code: String.t()}

  def version, do: @version
  def flows, do: Catalog.flow_keys()

  def limits,
    do: %{
      blocks: @max_blocks,
      rows_per_block: @max_rows,
      cells_per_row: @max_cells,
      text: @max_text,
      note: @max_note
    }

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
  of the section and its rows, or `{:error, errors}`.
  """
  @spec normalize(term()) :: {:ok, map()} | {:error, [error()]}
  def normalize(plan) do
    with :ok <- validate(plan) do
      {:ok, clean(plan)}
    end
  end

  @doc "Every problem of a plan, in the editor's order."
  @spec errors(term()) :: [error()]
  def errors(%{} = plan) do
    version = if Map.get(plan, "v") == @version, do: [], else: [error(["v"], "bad_version")]
    flow = Map.get(plan, "flow")

    if Catalog.flow?(flow) do
      Enum.concat([
        version,
        mods_errors(plan, flow),
        params_errors(plan, flow),
        score_errors(plan, flow),
        text_errors(plan, "note", @max_note, ["note"]),
        text_errors(plan, "preset", @max_text, ["preset"]),
        level_notes_errors(plan),
        blocks_errors(plan, flow),
        interrupt_errors(plan, flow),
        duplicate_id_errors(plan),
        structs_errors(plan, flow)
      ])
    else
      version ++ [error(["flow"], "unknown_flow")]
    end
  end

  def errors(_plan), do: [error([], "invalid")]

  @doc "Rows of a plan in order: every block's rows, then the interruption's."
  @spec rows(map()) :: [map()]
  def rows(%{} = plan) do
    plan
    |> list("blocks")
    |> Enum.flat_map(&List.wrap/1)
    |> Kernel.++(list(plan, "interrupt"))
    |> Enum.filter(&is_map/1)
  end

  def rows(_plan), do: []

  @doc """
  Row id => the block it is in (0-based), `-1` for an interruption row; what
  the execution checks plan actuals against. Only rows with an id.
  """
  @spec row_blocks(term()) :: %{String.t() => integer()}
  def row_blocks(%{} = plan) do
    blocks =
      plan
      |> list("blocks")
      |> Enum.with_index()
      |> Enum.flat_map(fn {rows, index} -> Enum.map(List.wrap(rows), &{&1, index}) end)

    (blocks ++ Enum.map(list(plan, "interrupt"), &{&1, -1}))
    |> Enum.flat_map(fn
      {%{"id" => id}, index} when is_binary(id) and id != "" -> [{id, index}]
      _other -> []
    end)
    |> Map.new()
  end

  def row_blocks(_plan), do: %{}

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

  @doc "A unit's key in `structs`: its group id, or its only row's id."
  @spec unit_key(%{group: String.t() | nil, rows: [map()]}) :: String.t() | nil
  def unit_key(%{group: group}) when is_binary(group), do: group
  def unit_key(%{rows: [row | _rest]}), do: Map.get(row, "id")

  @doc "The structure of a unit: the stated one when it fits (group or not), else the plain one."
  @spec struct_of(map(), map()) :: map()
  def struct_of(plan, unit) do
    group? = length(unit.rows) > 1

    case plan |> Map.get("structs") |> map_get(unit_key(unit)) do
      %{"kind" => kind} = struct when is_binary(kind) ->
        def = Catalog.struct(kind)
        if def && def.group == group?, do: struct, else: plain_struct(group?)

      _none ->
        plain_struct(group?)
    end
  end

  defp plain_struct(true), do: %{"kind" => "superset"}
  defp plain_struct(false), do: %{"kind" => "single"}

  @doc "How many exercise rows the plan's blocks hold (for summaries)."
  @spec exercise_count(term()) :: non_neg_integer()
  def exercise_count(%{} = plan) do
    plan
    |> list("blocks")
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.count(&(is_map(&1) and Map.get(&1, "kind") == "ex"))
  end

  def exercise_count(_plan), do: 0

  # ── section ──────────────────────────────────────────

  defp mods_errors(plan, flow) do
    allowed = Catalog.flow(flow).mods

    case Map.get(plan, "mods") do
      nil ->
        []

      %{} = mods ->
        mods
        |> Enum.sort()
        |> Enum.flat_map(fn
          {_mod, false} ->
            []

          {mod, true} ->
            if mod in allowed, do: [], else: [error(["mods", mod], "mod_not_allowed")]

          {mod, _other} ->
            [error(["mods", mod], "invalid")]
        end)

      _other ->
        [error(["mods"], "invalid")]
    end
  end

  defp params_errors(plan, flow) do
    case Map.get(plan, "params") do
      %{} = params ->
        active = Map.new(Catalog.param_defs(flow, Map.get(plan, "mods")), &{&1.key, &1})
        allowed = Catalog.allowed_params(flow)

        params
        |> Enum.sort()
        |> Enum.flat_map(fn {key, value} -> param_errors(key, value, active, allowed) end)

      _other ->
        [error(["params"], "invalid")]
    end
  end

  defp param_errors(key, value, active, allowed) do
    path = ["params", key]

    cond do
      not is_binary(value) ->
        [error(path, "invalid")]

      key not in allowed ->
        if String.trim(value) == "", do: [], else: [error(path, "unknown_param")]

      true ->
        too_long = if String.length(value) > @max_text, do: [error(path, "too_long")], else: []
        too_long ++ active_param_errors(Map.get(active, key), value, path)
    end
  end

  defp active_param_errors(nil, _value, _path), do: []

  defp active_param_errors(def, value, path),
    do: if(param_valid?(def, value), do: [], else: [error(path, "bad_param")])

  @doc "A typed param reads for its kind; empty is fine. A `time` may be two ascending durations."
  @spec param_valid?(map(), String.t()) :: boolean()
  def param_valid?(%{kind: kind} = def, value) do
    value = String.trim(value)
    value == "" or kind_valid?(kind, Map.get(def, :bare, :smart), value)
  end

  defp kind_valid?(:time, bare, value) do
    case Notation.parse_clock(value, bare) do
      seconds when is_integer(seconds) -> seconds > 0
      _bad -> match?(%{range: true}, Notation.parse_times(value, bare))
    end
  end

  defp kind_valid?(:times, bare, value), do: is_map(Notation.parse_times(value, bare))

  defp kind_valid?(:count, _bare, value),
    do: Regex.match?(~r/^\d+$/, value) and String.to_integer(value) > 0

  defp kind_valid?(:range, _bare, value) do
    case Regex.run(~r/^(\d+)(?:\s*-\s*(\d+))?$/, value) do
      [_all, min] -> String.to_integer(min) > 0
      [_all, min, max] -> ascending_counts?(min, max)
      nil -> false
    end
  end

  defp kind_valid?(:text, _bare, _value), do: true

  defp ascending_counts?(min, max) do
    min = String.to_integer(min)
    min > 0 and String.to_integer(max) >= min
  end

  defp score_errors(plan, flow) do
    preset = Map.get(plan, "preset")
    preset = if is_binary(preset), do: preset

    if Map.get(plan, "score") in Catalog.scores(flow, preset),
      do: [],
      else: [error(["score"], "unknown_score")]
  end

  defp level_notes_errors(plan) do
    case Map.get(plan, "levelNotes") do
      nil ->
        []

      %{} = notes when map_size(notes) > @max_level_notes ->
        [error(["levelNotes"], "invalid")]

      %{} = notes ->
        notes
        |> Enum.sort()
        |> Enum.flat_map(fn {level, _note} ->
          long =
            if String.length(level) > @max_text,
              do: [error(["levelNotes", level], "too_long")],
              else: []

          long ++ text_errors(notes, level, @max_note, ["levelNotes", level])
        end)

      _other ->
        [error(["levelNotes"], "invalid")]
    end
  end

  defp blocks_errors(plan, flow) do
    case Map.get(plan, "blocks") do
      blocks when is_list(blocks) ->
        rows? = Enum.any?(blocks, &(is_list(&1) and &1 != []))

        Enum.concat([
          if(Catalog.layout(flow) == :none and rows?,
            do: [error(["blocks"], "blocks_not_allowed")],
            else: []
          ),
          if(length(blocks) > @max_blocks, do: [error(["blocks"], "too_many_blocks")], else: []),
          blocks
          |> Enum.take(@max_blocks)
          |> Enum.with_index()
          |> Enum.flat_map(fn {block, index} ->
            rows_errors(block, ["blocks", index], flow, false)
          end)
        ])

      _other ->
        [error(["blocks"], "invalid")]
    end
  end

  defp interrupt_errors(plan, flow) do
    case Map.get(plan, "interrupt") do
      nil -> []
      rows -> rows_errors(rows, ["interrupt"], flow, true)
    end
  end

  defp rows_errors(rows, path, flow, interrupt?) when is_list(rows) do
    many = if length(rows) > @max_rows, do: [error(path, "too_many_rows")], else: []

    many ++
      (rows
       |> Enum.take(@max_rows)
       |> Enum.with_index()
       |> Enum.flat_map(fn {row, index} -> row_errors(row, path ++ [index], flow, interrupt?) end))
  end

  defp rows_errors(_rows, path, _flow, _interrupt?), do: [error(path, "invalid")]

  defp duplicate_id_errors(plan) do
    blocks =
      plan
      |> list("blocks")
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, b} -> indexed(block, ["blocks", b]) end)

    {errors, _seen} =
      Enum.reduce(
        blocks ++ indexed(list(plan, "interrupt"), ["interrupt"]),
        {[], MapSet.new()},
        fn
          {%{"id" => id}, path}, {acc, seen} when is_binary(id) ->
            if MapSet.member?(seen, id),
              do: {[error(path ++ ["id"], "duplicate_id") | acc], seen},
              else: {acc, MapSet.put(seen, id)}

          _row, acc ->
            acc
        end
      )

    Enum.reverse(errors)
  end

  defp indexed(rows, path) when is_list(rows),
    do: rows |> Enum.with_index() |> Enum.map(fn {row, i} -> {row, path ++ [i]} end)

  defp indexed(_rows, _path), do: []

  defp structs_errors(plan, flow) do
    case Map.get(plan, "structs") do
      nil ->
        []

      %{} = structs ->
        structs
        |> Enum.sort()
        |> Enum.flat_map(fn {key, struct} -> struct_errors(key, struct, flow) end)

      _other ->
        [error(["structs"], "invalid")]
    end
  end

  defp struct_errors(key, %{"kind" => kind} = struct, flow) when is_binary(kind) do
    path = ["structs", key]

    case Catalog.struct(kind) do
      nil ->
        [error(path, "unknown_struct")]

      def ->
        if kind != "single" and kind not in Catalog.flow(flow).structs do
          [error(path, "struct_not_allowed")]
        else
          Enum.flat_map(def.params, fn {field, field_kind} ->
            if struct_param_valid?(field_kind, Map.get(struct, field)),
              do: [],
              else: [error(path ++ [field], "bad_struct_param")]
          end)
        end
    end
  end

  defp struct_errors(key, _struct, _flow), do: [error(["structs", key], "unknown_struct")]

  defp struct_param_valid?(_kind, nil), do: true
  defp struct_param_valid?(_kind, value) when not is_binary(value), do: false

  defp struct_param_valid?(kind, value) do
    String.length(value) <= @max_text and struct_value_reads?(kind, String.trim(value))
  end

  defp struct_value_reads?(_kind, ""), do: true
  defp struct_value_reads?(:count, value), do: Regex.match?(~r/^\d+$/, value)
  defp struct_value_reads?(:time, value), do: is_integer(Notation.parse_clock(value, :smart))
  defp struct_value_reads?(:text, _value), do: true

  # ── rows ─────────────────────────────────────────────

  defp row_errors(%{} = row, path, flow, interrupt?) do
    measures = row_measures(row)
    cells? = not interrupt? and Catalog.uses_cells?(flow, row)

    Enum.concat([
      id_errors(row, path),
      if(Map.get(row, "kind") in ["ex", "rest"],
        do: [],
        else: [error(path ++ ["kind"], "bad_row_kind")]
      ),
      text_errors(row, "name", @max_text, path ++ ["name"]),
      text_errors(row, "exerciseRef", @max_text, path ++ ["exerciseRef"]),
      text_errors(row, "group", @max_text, path ++ ["group"]),
      text_errors(row, "note", @max_note, path ++ ["note"]),
      if(Map.get(row, "perRound") in [nil, true, false],
        do: [],
        else: [error(path ++ ["perRound"], "invalid")]
      ),
      extra_errors(row, path),
      cells_errors(row, path, measures, cells?),
      if(cells?, do: [], else: compact_errors(row, path, measures))
    ])
  end

  defp row_errors(_row, path, _flow, _interrupt?), do: [error(path, "invalid")]

  defp id_errors(%{"id" => id}, _path) when is_binary(id) and id != "", do: []
  defp id_errors(_row, path), do: [error(path ++ ["id"], "invalid")]

  @doc "A row's valued measures (known, not the `side` flag), once each, in order."
  @spec row_measures(map()) :: [String.t()]
  def row_measures(row) do
    case Map.get(row, "extra") do
      extra when is_list(extra) ->
        extra
        |> Enum.filter(&valued_measure?/1)
        |> Enum.uniq()

      _none ->
        []
    end
  end

  defp valued_measure?(key) when is_binary(key) do
    case Catalog.measure(key) do
      nil -> false
      measure -> not measure.flag
    end
  end

  defp valued_measure?(_key), do: false

  defp extra_errors(row, path) do
    case Map.get(row, "extra") do
      nil ->
        []

      extra when is_list(extra) ->
        {errors, _seen} =
          extra
          |> Enum.with_index()
          |> Enum.reduce({[], MapSet.new()}, fn {measure, i}, {acc, seen} ->
            extra_error(measure, path ++ ["extra", i], acc, seen)
          end)

        Enum.reverse(errors)

      _other ->
        [error(path ++ ["extra"], "invalid")]
    end
  end

  defp extra_error(measure, path, acc, seen) do
    cond do
      not is_binary(measure) or is_nil(Catalog.measure(measure)) ->
        {[error(path, "unknown_measure") | acc], seen}

      MapSet.member?(seen, measure) ->
        {[error(path, "duplicate_measure") | acc], seen}

      true ->
        {acc, MapSet.put(seen, measure)}
    end
  end

  defp cells_errors(row, path, measures, cells?) do
    case Map.get(row, "cells") do
      cells when is_list(cells) ->
        many =
          if length(cells) > @max_cells,
            do: [error(path ++ ["cells"], "too_many_cells")],
            else: []

        values =
          if cells?,
            do: cell_values_errors(row, cells, path, measures),
            else: cell_types_errors(cells, path)

        many ++ values

      nil ->
        []

      _other ->
        [error(path ++ ["cells"], "invalid")]
    end
  end

  # Cells the flow does not read are still bounded and typed.
  defp cell_types_errors(cells, path) do
    cells
    |> Enum.with_index()
    |> Enum.flat_map(fn {cell, j} -> cell_shape_errors(cell, path ++ ["cells", j]) end)
  end

  defp cell_shape_errors(nil, _path), do: []

  defp cell_shape_errors(%{} = cell, path) do
    cell
    |> Enum.sort()
    |> Enum.flat_map(fn
      {_key, nil} ->
        []

      {key, value} when not is_binary(value) ->
        [error(path ++ [key], "invalid")]

      {key, value} ->
        if String.length(value) > @max_text, do: [error(path ++ [key], "too_long")], else: []
    end)
  end

  defp cell_shape_errors(_cell, path), do: [error(path, "invalid")]

  defp cell_values_errors(row, cells, path, measures) do
    issues =
      if Map.get(row, "kind") == "ex",
        do: Notation.row_load_issues(Enum.map(cells, &cell_value(&1, "l"))).issues,
        else: %{}

    cells
    |> Enum.with_index()
    |> Enum.flat_map(fn {cell, j} ->
      cell_path = path ++ ["cells", j]

      Enum.concat([
        cell_shape_errors(cell, cell_path),
        dose_errors(cell_value(cell, "d"), cell_path ++ ["d"]),
        load_issue_errors(Map.get(issues, j), cell_path ++ ["l"]),
        Enum.flat_map(measures, fn key ->
          measure_errors(key, cell_value(cell, key), cell_path ++ [key], true)
        end)
      ])
    end)
  end

  defp load_issue_errors(nil, _path), do: []
  defp load_issue_errors(issue, path), do: [error(path, Atom.to_string(issue))]

  @doc "A cell's text value for a key (\"\" when missing)."
  @spec cell_value(term(), String.t()) :: String.t()
  def cell_value(%{} = cell, key) do
    case Map.get(cell, key) do
      value when is_binary(value) -> value
      _none -> ""
    end
  end

  def cell_value(_cell, _key), do: ""

  defp compact_errors(row, path, measures) do
    dose = Map.get(row, "dose")

    Enum.concat([
      text_errors(row, "dose", @max_text, path ++ ["dose"]),
      text_errors(row, "load", @max_text, path ++ ["load"]),
      if(is_binary(dose), do: dose_errors(dose, path ++ ["dose"]), else: []),
      compact_load_errors(row, path),
      x_errors(row, path, measures)
    ])
  end

  # The same-every-time load: a bare number has no unit to inherit.
  defp compact_load_errors(%{"kind" => "ex", "load" => load}, path) when is_binary(load) do
    if Regex.match?(~r/^\d+(?:[.,]\d+)?$/, String.trim(load)),
      do: [error(path ++ ["load"], "missing_unit")],
      else: []
  end

  defp compact_load_errors(_row, _path), do: []

  defp x_errors(row, path, measures) do
    case Map.get(row, "x") do
      nil ->
        []

      %{} = values ->
        Enum.flat_map(measures, fn key ->
          x_value_errors(Map.get(values, key), key, path ++ ["x", key])
        end)

      _other ->
        [error(path ++ ["x"], "invalid")]
    end
  end

  defp x_value_errors(nil, _key, _path), do: []
  defp x_value_errors(value, _key, path) when not is_binary(value), do: [error(path, "invalid")]

  defp x_value_errors(value, key, path) do
    if String.length(value) > @max_text,
      do: [error(path, "too_long")],
      else: measure_errors(key, value, path, false)
  end

  defp dose_errors(value, path) do
    if String.trim(value) != "" and Notation.parse_dose(value) == :bad,
      do: [error(path, "bad_dose")],
      else: []
  end

  defp measure_errors(key, value, path, in_cell?) do
    case measure_issue(key, value, in_cell?) do
      nil -> []
      code -> [error(path, code)]
    end
  end

  @doc """
  A measure value's problem, or nil: tempo has 4 marks; numeric measures start
  with a number (in per-set cells also `+x`/`-x`); RPE is at most 10.
  """
  @spec measure_issue(String.t(), String.t(), boolean()) :: String.t() | nil
  def measure_issue(key, value, in_cell?) do
    trimmed = String.trim(value)
    measure = Catalog.measure(key)
    numeric = if in_cell?, do: ~r/^[+-]?\d/, else: ~r/^\d/

    cond do
      trimmed == "" -> nil
      measure.text -> if Notation.tempo?(trimmed), do: nil, else: "bad_tempo"
      not Regex.match?(numeric, trimmed) -> "bad_measure_value"
      measure.max && over_max?(trimmed, measure.max) -> "rpe_over_max"
      true -> nil
    end
  end

  defp over_max?(value, max) do
    if Regex.match?(~r/^[+-]/, value) do
      false
    else
      ~r/\d+(?:\.\d+)?/
      |> Regex.scan(String.replace(value, ",", ".", global: false))
      |> Enum.any?(fn [number] -> elem(Float.parse(number), 0) > max end)
    end
  end

  # ── helpers ──────────────────────────────────────────

  defp text_errors(map, key, max, path) do
    case Map.get(map, key) do
      nil -> []
      value when is_binary(value) -> length_errors(value, max, path)
      _other -> [error(path, "invalid")]
    end
  end

  defp length_errors(value, max, path) do
    cond do
      String.length(value) <= max -> []
      max == @max_note -> [error(path, "note_too_long")]
      true -> [error(path, "too_long")]
    end
  end

  defp list(plan, key) do
    case Map.get(plan, key) do
      list when is_list(list) -> list
      _none -> []
    end
  end

  defp map_get(%{} = map, key) when is_binary(key), do: Map.get(map, key)
  defp map_get(_map, _key), do: nil

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
