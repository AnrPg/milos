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

  @doc """
  Every problem of a plan, as the web `validateSection` reports it. Accepts
  any value and never raises: a wrong shape is `bad_shape` and reads as empty.
  """
  @spec errors(term()) :: [error()]
  def errors(%{} = plan), do: section_errors(plan)
  def errors(_plan), do: [error("", "bad_shape")]

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

  # The score types of a plan score key, as the web runner records them
  # (`plan/score.ts` `scoreConfig`); `none` is not scored.
  @score_types %{
    "time" => %{"type" => "time"},
    "rounds_reps" => %{"type" => "rounds_reps"},
    "reps" => %{"type" => "reps"},
    "total_reps" => %{"type" => "reps"},
    "lowest_round" => %{"type" => "reps"},
    "best_load" => %{"type" => "load", "unit" => "kg"},
    "done" => %{"type" => "pass_fail"},
    "distance" => %{"type" => "reps", "unit" => "m"}
  }

  @doc """
  The section score of a plan, as a section `score_config`
  (`%{"type" => type}` plus `"unit"` when it has one, and the plan's own
  `"plan_score"` key); nil when the plan is not scored.
  """
  @spec score_config(term()) :: map() | nil
  def score_config(%{"score" => score}) when is_map_key(@score_types, score),
    do: @score_types |> Map.fetch!(score) |> Map.put("plan_score", score)

  def score_config(_plan), do: nil

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

  # ── validation (validate.ts, rule for rule) ─────────

  # A JSON object (not a list).
  defp obj?(value), do: is_map(value)

  # JS string length (UTF-16 code units).
  defp js_length(value),
    do: div(byte_size(:unicode.characters_to_binary(value, :utf8, :utf16)), 2)

  defp too_long?(value, max \\ @max_text), do: js_length(value) > max

  # A string field: nil is "", anything else not a string is `bad_shape`.
  defp str(value, path, acc, max \\ @max_text, code \\ "too_long")
  defp str(nil, _path, acc, _max, _code), do: {"", acc}

  defp str(value, path, acc, max, code) when is_binary(value) do
    if too_long?(value, max), do: {value, [error(path, code) | acc]}, else: {value, acc}
  end

  defp str(_value, path, acc, _max, _code), do: {"", [error(path, "bad_shape") | acc]}

  defp arr(nil, _path, acc), do: {[], acc}
  defp arr(value, _path, acc) when is_list(value), do: {value, acc}
  defp arr(_value, path, acc), do: {[], [error(path, "bad_shape") | acc]}

  defp obj(nil, _path, acc), do: {%{}, acc}
  defp obj(%{} = value, _path, acc), do: {value, acc}
  defp obj(_value, path, acc), do: {%{}, [error(path, "bad_shape") | acc]}

  defp js_truthy(value), do: value not in [nil, false, 0, "", +0.0]

  defp section_errors(section) do
    acc = if section["v"] == @version, do: [], else: [error("v", "bad_version")]
    flow = section["flow"]

    if is_binary(flow) and Catalog.flow?(flow) do
      section
      |> flow_errors(flow, acc)
      |> Enum.reverse()
    else
      Enum.reverse([error("flow", "unknown_flow") | acc])
    end
  end

  defp flow_errors(section, flow, acc) do
    spec = Catalog.flow(flow)
    {mods, acc} = obj(section["mods"], "mods", acc)

    acc =
      Enum.reduce(mods, acc, fn {mod, on}, acc ->
        cond do
          on != nil and not is_boolean(on) ->
            [error("mods.#{mod}", "bad_shape") | acc]

          js_truthy(on) and mod not in spec.mods ->
            [error("mods.#{mod}", "mod_not_allowed") | acc]

          true ->
            acc
        end
      end)

    acc = params_errors(section, flow, mods, acc)
    {score, acc} = str(section["score"], "score", acc)
    {preset, acc} = str(section["preset"], "preset", acc)

    acc =
      if score in Catalog.scores(flow, if(preset == "", do: nil, else: preset)),
        do: acc,
        else: [error("score", "unknown_score") | acc]

    {_note, acc} = str(section["note"], "note", acc, @max_note, "note_too_long")
    {level_notes, acc} = obj(section["levelNotes"], "levelNotes", acc)

    acc =
      Enum.reduce(level_notes, acc, fn {level, note}, acc ->
        acc = if too_long?(level), do: [error("levelNotes.#{level}", "too_long") | acc], else: acc
        {_note, acc} = str(note, "levelNotes.#{level}", acc, @max_note, "note_too_long")
        acc
      end)

    {blocks, acc} = arr(section["blocks"], "blocks", acc)

    acc =
      if Catalog.layout(flow) == :none and Enum.any?(blocks, &(is_list(&1) and &1 != [])),
        do: [error("blocks", "blocks_not_allowed") | acc],
        else: acc

    acc =
      if length(blocks) > @max_blocks, do: [error("blocks", "too_many_blocks") | acc], else: acc

    {acc, ids} =
      blocks
      |> Enum.with_index()
      |> Enum.reduce({acc, MapSet.new()}, fn {block, i}, {acc, ids} ->
        {rows, acc} = arr(block, "blocks.#{i}", acc)
        take_rows(rows, "blocks.#{i}", flow, false, acc, ids)
      end)

    {interrupt, acc} = arr(section["interrupt"], "interrupt", acc)
    {acc, _ids} = take_rows(interrupt, "interrupt", flow, true, acc, ids)
    structs_errors(section, spec, acc)
  end

  defp params_errors(section, flow, mods, acc) do
    active = Map.new(Catalog.param_defs(flow, mods, &js_truthy/1), &{&1.key, &1})
    allowed = Catalog.allowed_params(flow)
    {params, acc} = obj(section["params"], "params", acc)

    Enum.reduce(params, acc, fn {key, raw}, acc ->
      path = "params.#{key}"
      {value, acc} = str(raw, path, acc)

      cond do
        key not in allowed ->
          if String.trim(value) != "", do: [error(path, "unknown_param") | acc], else: acc

        (def = Map.get(active, key)) && is_binary(raw) && not read_param(def, value).ok ->
          [error(path, "bad_param") | acc]

        true ->
          acc
      end
    end)
  end

  defp take_rows(rows, base, flow, interrupt?, acc, ids) do
    acc = if length(rows) > @max_rows, do: [error(base, "too_many_rows") | acc], else: acc

    rows
    |> Enum.with_index()
    |> Enum.reduce({acc, ids}, fn {raw, i}, {acc, ids} ->
      path = "#{base}.#{i}"

      case read_row(raw, path, acc) do
        {nil, acc} ->
          {acc, ids}

        {row, acc} ->
          acc =
            if row["id"] != "" and MapSet.member?(ids, row["id"]),
              do: [error("#{path}.id", "duplicate_id") | acc],
              else: acc

          {validate_row(flow, row, path, interrupt?, acc), MapSet.put(ids, row["id"])}
      end
    end)
  end

  @cell_keys ~w(d l pace tempo rpe rir zone height dist hold)
  @measure_keys ~w(pace tempo rpe rir zone height dist hold side)

  # A row read into the contract's shape (junk dropped, reported).
  defp read_row(raw, path, acc) when not is_map(raw), do: {nil, [error(path, "bad_shape") | acc]}

  defp read_row(raw, path, acc) do
    at = &"#{path}.#{&1}"

    id =
      case raw["id"] do
        id when is_binary(id) -> if String.trim(id) != "", do: id, else: ""
        _other -> ""
      end

    acc =
      cond do
        id == "" -> [error(at.("id"), "bad_shape") | acc]
        too_long?(id) -> [error(at.("id"), "too_long") | acc]
        true -> acc
      end

    kind = if raw["kind"] in ["ex", "rest"], do: raw["kind"]
    acc = if kind, do: acc, else: [error(at.("kind"), "bad_row_kind") | acc]
    {cells_raw, acc} = arr(raw["cells"], at.("cells"), acc)

    acc =
      if length(cells_raw) > @max_cells,
        do: [error(at.("cells"), "too_many_cells") | acc],
        else: acc

    {cells, acc} =
      cells_raw
      |> Enum.take(@max_cells)
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {cell, j}, acc -> read_cell(cell, at.("cells.#{j}"), acc) end)

    {x_raw, acc} = obj(raw["x"], at.("x"), acc)

    {x, acc} =
      Enum.reduce(x_raw, {%{}, acc}, fn {key, value}, {x, acc} ->
        if key in @cell_keys and key not in ["d", "l"] do
          {value, acc} = str(value, at.("x.#{key}"), acc)
          {Map.put(x, key, value), acc}
        else
          {x, [error(at.("x.#{key}"), "bad_shape") | acc]}
        end
      end)

    {extra_raw, acc} = arr(raw["extra"], at.("extra"), acc)

    {extra, _seen, acc} =
      extra_raw
      |> Enum.with_index()
      |> Enum.reduce({[], MapSet.new(), acc}, fn {key, i}, {extra, seen, acc} ->
        {extra, acc} =
          cond do
            not is_binary(key) or key not in @measure_keys ->
              {extra, [error(at.("extra.#{i}"), "unknown_measure") | acc]}

            MapSet.member?(seen, key) ->
              {extra, [error(at.("extra.#{i}"), "duplicate_measure") | acc]}

            true ->
              {extra ++ [key], acc}
          end

        {extra, if(is_binary(key), do: MapSet.put(seen, key), else: seen), acc}
      end)

    acc =
      if raw["perRound"] != nil and not is_boolean(raw["perRound"]),
        do: [error(at.("perRound"), "bad_shape") | acc],
        else: acc

    acc =
      if raw["group"] != nil and not is_binary(raw["group"]),
        do: [error(at.("group"), "bad_shape") | acc],
        else: acc

    {name, acc} = str(raw["name"], at.("name"), acc)
    {ref, acc} = str(raw["exerciseRef"], at.("exerciseRef"), acc)
    {dose, acc} = str(raw["dose"], at.("dose"), acc)
    {load, acc} = str(raw["load"], at.("load"), acc)
    {note, acc} = str(raw["note"], at.("note"), acc, @max_note, "note_too_long")

    row = %{
      "id" => id,
      "kind" => kind || "ex",
      "name" => name,
      "exerciseRef" => if(ref == "", do: nil, else: ref),
      "dose" => dose,
      "load" => load,
      "x" => x,
      "extra" => extra,
      "cells" => cells,
      "perRound" => raw["perRound"] == true,
      "group" => if(is_binary(raw["group"]), do: raw["group"]),
      "note" => note
    }

    {row, acc}
  end

  defp read_cell(nil, _path, acc), do: {%{}, acc}

  defp read_cell(cell, path, acc) when not is_map(cell),
    do: {%{}, [error(path, "bad_shape") | acc]}

  defp read_cell(cell, path, acc) do
    Enum.reduce(cell, {%{}, acc}, fn {key, value}, {out, acc} ->
      if key in @cell_keys do
        {value, acc} = str(value, "#{path}.#{key}", acc)
        {Map.put(out, key, value), acc}
      else
        {out, [error("#{path}.#{key}", "bad_shape") | acc]}
      end
    end)
  end

  defp validate_row(flow, row, path, interrupt?, acc) do
    at = &"#{path}.#{&1}"
    measures = Enum.reject(row["extra"], &Catalog.measure(&1).flag)

    if not interrupt? and Catalog.uses_cells?(flow, row) do
      cells = row["cells"]
      n = length(cells)
      load_errors = if row["kind"] == "ex", do: Notation.set_loads(row, n).errors, else: []

      measure_errors =
        Map.new(
          measures,
          &{&1, Notation.measure_cell_errors(row, &1, n, Catalog.measure(&1).clock)}
        )

      cells
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {cell, j}, acc ->
        d = Map.get(cell, "d", "")

        acc =
          if d != "" and Notation.parse_dose(d) == :bad,
            do: [error(at.("cells.#{j}.d"), "bad_dose") | acc],
            else: acc

        acc =
          case Enum.at(load_errors, j) do
            nil -> acc
            code -> [error(at.("cells.#{j}.l"), code) | acc]
          end

        Enum.reduce(measures, acc, fn key, acc ->
          code =
            measure_issue(key, Map.get(cell, key, ""), true) ||
              if(Catalog.measure(key).text, do: nil, else: Enum.at(measure_errors[key], j))

          if code, do: [error(at.("cells.#{j}.#{key}"), code) | acc], else: acc
        end)
      end)
    else
      acc =
        if row["dose"] != "" and Notation.parse_dose(row["dose"]) == :bad,
          do: [error(at.("dose"), "bad_dose") | acc],
          else: acc

      acc =
        if row["kind"] == "ex" do
          cond do
            match?(%{kind: "wrong"}, Notation.parse_load(row["load"])) ->
              [error(at.("load"), "wrong_unit") | acc]

            Regex.match?(~r/^[0-9]+(?:\.[0-9]+)?$/, Notation.decimal_comma_norm(row["load"])) ->
              [error(at.("load"), "missing_unit") | acc]

            true ->
              acc
          end
        else
          acc
        end

      Enum.reduce(measures, acc, fn key, acc ->
        case measure_issue(key, Map.get(row["x"], key, ""), false) do
          nil -> acc
          code -> [error(at.("x.#{key}"), code) | acc]
        end
      end)
    end
  end

  defp structs_errors(section, spec, acc) do
    {structs, acc} = obj(section["structs"], "structs", acc)

    Enum.reduce(structs, acc, fn {key, st}, acc ->
      path = "structs.#{key}"
      def = if obj?(st) and is_binary(st["kind"]), do: Catalog.struct(st["kind"])

      if is_nil(def) do
        [error(path, "unknown_struct") | acc]
      else
        acc =
          if st["kind"] != "single" and st["kind"] not in spec.structs,
            do: [error(path, "struct_not_allowed") | acc],
            else: acc

        Enum.reduce(def.params, acc, fn {field, kind}, acc ->
          {value, acc} = str(st[field], "#{path}.#{field}", acc)

          ok =
            String.trim(value) == "" or
              case kind do
                :count ->
                  Notation.parse_count(value) != nil

                :time ->
                  match?(
                    secs when is_number(secs) and secs > 0,
                    Notation.parse_clock(value, :smart)
                  )

                :text ->
                  true
              end

          if ok, do: acc, else: [error("#{path}.#{field}", "bad_struct_param") | acc]
        end)
      end
    end)
  end

  @doc """
  How a typed parameter reads for its kind (`readParam`): `%{ok: false}`,
  or `%{ok: true, kind: :empty | :secs | :secs_range | :windows | :count |
  :count_range | :text, ...}` with `ambiguous` where a bare number or two
  rising AMRAP windows could mean something else.
  """
  @spec read_param(map(), term()) :: map()
  def read_param(_def, value) when not is_binary(value), do: %{ok: false}

  def read_param(%{kind: kind} = def, value) do
    bare = Map.get(def, :bare, :smart)

    if Notation.norm_text(value) == "" do
      %{ok: true, kind: :empty}
    else
      read_kind(kind, bare, value)
    end
  end

  defp read_kind(:time, bare, value) do
    case Notation.parse_clock(value, bare) do
      secs when is_number(secs) and secs <= 0 ->
        %{ok: false}

      secs when is_number(secs) ->
        amb = if bare == :smart, do: Notation.clock_ambiguity(value, bare)
        out = %{ok: true, kind: :secs, secs: secs}
        if amb, do: Map.put(out, :ambiguous, amb), else: out

      _other ->
        case Notation.parse_times(value, bare) do
          %{range: true, secs: [min, max]} -> %{ok: true, kind: :secs_range, min: min, max: max}
          _other -> %{ok: false}
        end
    end
  end

  defp read_kind(:times, bare, value) do
    case Notation.parse_times(value, bare) do
      %{range: true, secs: secs} ->
        write = Notation.clock(hd(secs))
        list = Enum.map_join(secs, " · ", &Notation.clock/1)

        %{
          ok: true,
          kind: :windows,
          secs: secs,
          ambiguous: %{
            alt: "range",
            write: write,
            hint: %{
              key: "PlanCore.ambiguous.windows",
              values: %{count: 2, list: list, write: write}
            }
          }
        }

      %{secs: secs} ->
        %{ok: true, kind: :windows, secs: secs}

      _other ->
        %{ok: false}
    end
  end

  defp read_kind(:count, _bare, value) do
    case Notation.parse_count(value) do
      nil -> %{ok: false}
      n -> %{ok: true, kind: :count, n: n}
    end
  end

  defp read_kind(:range, _bare, value) do
    case Notation.parse_count_range(value) do
      nil -> %{ok: false}
      range -> Map.merge(%{ok: true, kind: :count_range}, range)
    end
  end

  defp read_kind(:text, _bare, value), do: %{ok: true, kind: :text, text: String.trim(value)}

  @doc "A typed param reads for its kind; empty is fine (`read_param/2`)."
  @spec param_valid?(map(), term()) :: boolean()
  def param_valid?(def, value), do: read_param(def, value).ok

  @doc "A row's valued measures (known, not the `side` flag), once each, in order."
  @spec row_measures(map()) :: [String.t()]
  def row_measures(row) do
    case Map.get(row, "extra") do
      extra when is_list(extra) ->
        extra
        |> Enum.filter(
          &(is_binary(&1) and Catalog.measure(&1) != nil and not Catalog.measure(&1).flag)
        )
        |> Enum.uniq()

      _none ->
        []
    end
  end

  @doc "A cell's text value for a key (\"\" when missing)."
  @spec cell_value(term(), String.t()) :: String.t()
  def cell_value(%{} = cell, key) do
    case Map.get(cell, key) do
      value when is_binary(value) -> value
      _none -> ""
    end
  end

  def cell_value(_cell, _key), do: ""

  @doc """
  A measure value's problem, or nil: tempo has 4 marks; numeric measures
  start with a number (a zone may say \"z2\"; in cells also `+x`/`-x`); RPE
  is at most 10. A value that is not a string is `bad_shape`.
  """
  @spec measure_issue(String.t(), term(), boolean()) :: String.t() | nil
  def measure_issue(_key, nil, _in_cell?), do: nil
  def measure_issue(_key, value, _in_cell?) when not is_binary(value), do: "bad_shape"

  def measure_issue(key, value, in_cell?) do
    t =
      value
      |> Notation.decimal_comma_norm()
      |> then(&Regex.replace(~r/^z(?:one)?\s*(?=[0-9])/, &1, ""))

    measure = Catalog.measure(key)
    numeric = if in_cell?, do: ~r/^[+-]?[0-9]/, else: ~r/^[0-9]/

    cond do
      t == "" -> nil
      measure.text -> if Notation.tempo_parts(value), do: nil, else: "bad_tempo"
      not Regex.match?(numeric, t) -> "bad_measure_value"
      measure.max && not Regex.match?(~r/^[+-]/, t) && over_max?(t, measure.max) -> "rpe_over_max"
      true -> nil
    end
  end

  defp over_max?(t, max) do
    ~r/[0-9]+(?:\.[0-9]+)?/
    |> Regex.scan(t)
    |> Enum.any?(fn [number] -> Notation.to_num(number) > max end)
  end

  # ── helpers ──────────────────────────────────────────

  defp list(plan, key) do
    case Map.get(plan, key) do
      list when is_list(list) -> list
      _none -> []
    end
  end

  defp map_get(%{} = map, key) when is_binary(key), do: Map.get(map, key)
  defp map_get(_map, _key), do: nil

  defp error(path, code), do: %{path: path, code: code}

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
