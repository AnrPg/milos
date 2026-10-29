defmodule Palee.Workouts.Domain.StructuredPlan.Prescription do
  @moduledoc """
  The canonical read model of a structured plan section (ADR-270), pure.

  A plan keeps what the coach typed ("12-10-8", "+5", "60→80%", "2:00/500m").
  Every consumer that needs numbers (the WOD executor, progress tracking,
  analytics, the legacy `workout_exercises` columns) reads this instead of
  re-parsing the text. `build/1` expands a valid plan into:

  * `clock` — how the section runs, unit-normalised: `flow`, `sets`
    (`%{min, max}`), `rest_secs` (`%{min, max}`), `rounds`, `cap_secs`,
    `windows_secs` (AMRAP), `every_secs`/`times` (EMOM), `work_secs`/
    `off_secs` (intervals), `dur_secs` (rest), `interrupt_every_secs`,
    `hr_target_bpm`, `open_ended` (AMRAP, EMOM without times) and
    `total_rounds` (nil when open-ended: never an invented count);
  * `rows` — every row in order (blocks, then the interruption's with
    `block_index` -1): `row_id`, `kind` (exercise | rest), `name`,
    `exercise_ref`, `note`, `group_id`, `structure` (kind and its params:
    `clusters`, `intra_secs`, `drops`, `drop_by`, `minis`), `per_side`, and
    `sets`: one per set / round column, each with `index` (1-based), the
    `rounds` (1-based round numbers) it applies to, `reps` (`min`, `max`,
    `unit` reps | secs | meters | kcal, `max_effort`, `within_secs`, `sets` written inside the dose as in
    "4×10", `text`),
    `load` (`kind` kg | pct_1rm | bodyweight | qualitative, `value` and
    `value_max` as `Decimal`, `text`), `rest_secs` (rest rows) and canonical
    `measures` (`pace_secs_per_500m`, `tempo` in 4 parts, `rpe`, `rir`,
    `hr_zone`, `height_cm`, `distance_m`, `hold_secs`);
  * `then` on rows of an open-ended section — what follows the written
    rounds: `%{rule: "repeat"}`, or `%{rule: "step", reps_step, load_step}`
    when the coach wrote a progression ("1-2-3…", "+5").

  Column rules are the editor's: an empty value repeats the one before (or
  keeps adding the last `+x`, or keeps spreading `a→b` to the last column);
  the load unit is written once per row. At most 12 columns per block; the
  last column applies to every later round of its block.
  """

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.{Catalog, Notation}

  @max_columns 12
  # Round numbers listed for one column, for very long EMOMs and intervals.
  @max_listed_rounds 200
  @measure_keys ~w(pace tempo rpe rir zone height dist hold)

  @type section :: %{clock: map(), rows: [map()]}

  @doc "The read model of a valid plan (see the module doc), or nil for anything else."
  @spec build(term()) :: section() | nil
  def build(%{"flow" => flow} = plan) when is_binary(flow) do
    if Catalog.flow?(flow) do
      clock = clock(plan)
      blocks = list(plan, "blocks")

      block_rows =
        blocks
        |> Enum.with_index()
        |> Enum.flat_map(fn {rows, b} -> unit_rows(plan, clock, rows, b) end)

      interrupt_rows = unit_rows(plan, clock, list(plan, "interrupt"), -1)

      %{clock: clock, rows: block_rows ++ interrupt_rows}
    end
  end

  def build(_plan), do: nil

  @doc "The read model as JSON-ready maps (decimals as numbers)."
  @spec to_json(section() | nil) :: map() | nil
  def to_json(nil), do: nil
  def to_json(section), do: json(section)

  defp json(%Decimal{} = decimal), do: decimal |> Decimal.normalize() |> decimal_number()
  defp json(%{} = map), do: Map.new(map, fn {key, value} -> {key, json(value)} end)
  defp json(list) when is_list(list), do: Enum.map(list, &json/1)
  defp json(value), do: value

  defp decimal_number(decimal) do
    if Decimal.integer?(decimal), do: Decimal.to_integer(decimal), else: Decimal.to_float(decimal)
  end

  # ── clock ────────────────────────────────────────────

  @doc "How a section's clock runs, unit-normalised."
  @spec clock(map()) :: map()
  def clock(%{"flow" => flow} = plan) do
    params = if is_map(plan["params"]), do: plan["params"], else: %{}
    mods = if is_map(plan["mods"]), do: plan["mods"], else: %{}
    times = count(params["times"])
    open = flow == "amrap" or (flow == "emom" and is_nil(times))

    %{
      flow: flow,
      preset: string(plan["preset"]),
      score: string(plan["score"]),
      sets: if(flow == "sets", do: sets_range(params["sets"])),
      rest_secs: if(flow in ["sets", "amrap"], do: time_range(params["rest"], :smart)),
      rounds: if(flow in ["for_time", "intervals"], do: count(params["rounds"]) || 1),
      cap_secs: if(flow == "for_time", do: seconds(params["cap"], :min)),
      windows_secs: if(flow == "amrap", do: windows(params["dur"])),
      every_secs: if(flow == "emom", do: seconds(params["every"], :smart)),
      times: if(flow == "emom", do: times),
      work_secs: if(flow == "intervals", do: seconds(params["work"], :smart)),
      off_secs: if(flow == "intervals", do: seconds(params["off"], :smart)),
      dur_secs: if(flow == "rest", do: seconds(params["dur"], :smart)),
      interrupt_every_secs:
        if(mods["interrupt"] == true, do: seconds(params["intEvery"], :smart)),
      hr_target_bpm: if(mods["hr"] == true, do: count(params["hrTarget"])),
      blocks: plan |> list("blocks") |> length(),
      open_ended: open,
      total_rounds: total_rounds(flow, params, open)
    }
  end

  defp total_rounds(_flow, _params, true), do: nil
  defp total_rounds("sets", params, false), do: sets_range(params["sets"]).max
  defp total_rounds("emom", params, false), do: count(params["times"])
  defp total_rounds("rest", _params, false), do: 0
  defp total_rounds(_flow, params, false), do: count(params["rounds"]) || 1

  defp sets_range(text), do: Notation.parse_count_range(text) || %{min: 1, max: 1}

  defp count(text), do: Notation.parse_count(text)

  defp seconds(text, bare) when is_binary(text) do
    case Notation.parse_clock(text, bare) do
      secs when is_number(secs) and secs > 0 -> round_number(secs)
      _other -> nil
    end
  end

  defp seconds(_text, _bare), do: nil

  defp time_range(text, bare) when is_binary(text) do
    case Notation.parse_times(text, bare) do
      %{range: true, secs: [min, max]} -> %{min: round_number(min), max: round_number(max)}
      %{secs: [secs]} when secs > 0 -> %{min: round_number(secs), max: round_number(secs)}
      _other -> nil
    end
  end

  defp time_range(_text, _bare), do: nil

  defp windows(text) when is_binary(text) do
    case Notation.parse_times(text, :min) do
      %{secs: secs} -> Enum.map(secs, &round_number/1)
      _other -> []
    end
  end

  defp windows(_text), do: []

  # ── rows ─────────────────────────────────────────────

  defp unit_rows(plan, clock, rows, block_index) do
    rows = if is_list(rows), do: Enum.filter(rows, &is_map/1), else: []
    rounds = block_rounds(plan, clock, rows, block_index)

    rows
    |> StructuredPlan.units()
    |> Enum.flat_map(fn unit ->
      structure = structure(StructuredPlan.struct_of(plan, unit))

      Enum.map(unit.rows, fn row ->
        row(plan, clock, row, block_index, rounds, unit.group, structure)
      end)
    end)
  end

  # The rounds (1-based) each column of a block applies to; the last column
  # also covers the block's later rounds. Open-ended: the written columns.
  defp block_rounds(_plan, _clock, _rows, -1), do: [[]]

  defp block_rounds(plan, clock, rows, b) do
    k = max(1, clock.blocks)

    if clock.open_ended do
      columns = max(1, written_columns(plan["flow"], rows))
      Enum.map(0..(columns - 1), fn i -> [b + 1 + i * k] end)
    else
      all =
        b
        |> Stream.iterate(&(&1 + k))
        |> Stream.take_while(&(&1 < clock.total_rounds))
        |> Stream.map(&(&1 + 1))
        |> Enum.take(@max_listed_rounds)

      {head, tail} = Enum.split(all, @max_columns - 1)
      Enum.map(head, &[&1]) ++ if(tail == [], do: [], else: [tail])
    end
  end

  # Columns the coach wrote in a block: cells, or a dose with one value per
  # round ("1-2-3…").
  defp written_columns(flow, rows) do
    rows
    |> Enum.map(fn row ->
      if Catalog.uses_cells?(flow, row) do
        row
        |> list("cells")
        |> Enum.with_index(1)
        |> Enum.reduce(0, fn {cell, i}, acc -> if written?(cell), do: i, else: acc end)
      else
        row["dose"] |> string() |> parse_or_nil() |> dose_columns()
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> min(@max_columns)
  end

  defp written?(%{} = cell),
    do: Enum.any?(cell, fn {_key, value} -> is_binary(value) and String.trim(value) != "" end)

  defp written?(_cell), do: false

  defp row(plan, clock, row, block_index, rounds, group, structure) do
    cells? = block_index >= 0 and Catalog.uses_cells?(plan["flow"], row)
    kind = if row["kind"] == "rest", do: "rest", else: "exercise"
    measures = StructuredPlan.row_measures(row)

    columns =
      if cells?,
        do: cell_columns(row, measures, rounds),
        else: compact_columns(row, measures, rounds)

    dose = Notation.parse_dose(string(row["dose"]) || "")

    %{
      row_id: row["id"],
      kind: kind,
      name: blank_to_nil(row["name"]),
      exercise_ref: blank_to_nil(row["exerciseRef"]),
      note: blank_to_nil(row["note"]),
      block_index: block_index,
      interrupt: block_index == -1,
      group_id: group,
      structure: structure,
      per_side: "side" in list(row, "extra") or per_side?(columns.doses),
      sets: Enum.map(columns.sets, &set_for(&1, kind)),
      then: if(clock.open_ended and block_index >= 0, do: then_rule(cells?, columns, dose))
    }
  end

  defp per_side?(doses), do: Enum.any?(doses, &match?(%{per_side: true}, &1))

  defp set_for(set, "rest"),
    do: set |> Map.put(:rest_secs, rest_secs(set.reps)) |> Map.merge(%{reps: nil, load: nil})

  defp set_for(set, _exercise), do: Map.put(set, :rest_secs, nil)

  defp rest_secs(%{unit: "secs", min: secs}), do: secs
  defp rest_secs(_reps), do: nil

  # Per set / per round: the cells, with the editor's column rules.
  defp cell_columns(row, measures, rounds) do
    n = length(rounds)
    doses = row |> Notation.repeat_text("d", n) |> Enum.map(&blank_to_nil/1)
    loads = cell_loads(row, n)
    measure_values = Map.new(measures, fn key -> {key, measure_column(row, key, n)} end)

    sets =
      rounds
      |> Enum.with_index()
      |> Enum.map(fn {round_numbers, i} ->
        %{
          index: i + 1,
          rounds: round_numbers,
          reps: reps(Enum.at(doses, i), 0),
          load: Enum.at(loads.values, i),
          measures: measures_at(measure_values, i)
        }
      end)

    %{sets: sets, doses: Enum.map(doses, &parse_or_nil/1), load_step: loads.step}
  end

  # The same values every time; a dose with one value per round ("21-15-9")
  # or a progression ("1-2-3…") still changes per round.
  defp compact_columns(row, measures, rounds) do
    dose = parse_or_nil(string(row["dose"]))
    load = Notation.parse_load(string(row["load"]))
    x = if is_map(row["x"]), do: row["x"], else: %{}

    values =
      Enum.reduce(measures, empty_measures(), fn key, acc ->
        put_measure(acc, key, canonical(key, x[key]))
      end)

    sets =
      rounds
      |> Enum.with_index()
      |> Enum.map(fn {round_numbers, i} ->
        %{
          index: i + 1,
          rounds: round_numbers,
          reps: reps(dose, i),
          load: load && compact_load(load, i),
          measures: values
        }
      end)
      |> merge_same()

    %{sets: sets, doses: [dose], load_step: nil}
  end

  defp dose_columns(%{entries: entries}) when is_list(entries),
    do: min(length(entries), @max_columns)

  defp dose_columns(_dose), do: 0

  # Consecutive identical rounds become one set (an EMOM of 10 × 15 reps).
  defp merge_same(sets) do
    sets
    |> Enum.reduce([], fn
      set, [last | rest] when last.reps == set.reps and last.load == set.load ->
        [%{last | rounds: last.rounds ++ set.rounds} | rest]

      set, acc ->
        [set | acc]
    end)
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {set, index} -> %{set | index: index} end)
  end

  defp then_rule(cells?, columns, dose) do
    reps_step = if cells?, do: nil, else: dose_step(dose)
    load_step = columns.load_step

    if reps_step || load_step,
      do: %{rule: "step", reps_step: reps_step, load_step: load_step},
      else: %{rule: "repeat", reps_step: nil, load_step: nil}
  end

  defp dose_step(%{cont: true, entries: [_, _ | _] = entries}) do
    [a, b] = Enum.take(entries, -2)
    round_number(b.min - a.min)
  end

  defp dose_step(_dose), do: nil

  # ── reps ─────────────────────────────────────────────

  defp parse_or_nil(nil), do: nil

  defp parse_or_nil(text) do
    case Notation.parse_dose(text) do
      %{} = dose -> dose
      _other -> nil
    end
  end

  defp reps(nil, _i), do: nil
  defp reps(text, i) when is_binary(text), do: reps(parse_or_nil(text), i)

  defp reps(%{max: %{within: within}} = dose, _i) do
    %{
      min: nil,
      max: nil,
      unit: unit(dose.unit),
      max_effort: true,
      within_secs: within && round_number(within),
      sets: dose.sets,
      text: nil
    }
  end

  defp reps(%{entries: [_ | _]} = dose, i) do
    entry = Notation.entry_at(dose, i)

    %{
      min: round_number(entry.min),
      max: round_number(entry.max),
      unit: unit(dose.unit),
      max_effort: false,
      within_secs: nil,
      sets: dose.sets,
      text: nil
    }
  end

  defp reps(_dose, _i), do: nil

  defp unit("m"), do: "meters"
  defp unit(unit), do: unit

  # ── load ─────────────────────────────────────────────

  # The editor's `setLoads` as numbers: empty repeats (or keeps adding the
  # last +x, or keeps spreading a→b), words pass through.
  defp cell_loads(row, n) do
    %{readings: readings, step: step} = Notation.set_load_readings(row, n)
    %{values: Enum.map(readings, &reading_load/1), step: step && decimal(step)}
  end

  defp reading_load(%{kind: :value, value: value, unit: unit}),
    do: numeric_load(value, nil, unit, nil)

  defp reading_load(%{kind: :up, value: value, unit: unit}),
    do: numeric_load(value, nil, unit, "up")

  defp reading_load(%{kind: :range, min: min, max: max, unit: unit}),
    do: numeric_load(min, max, unit, nil)

  defp reading_load(%{kind: :words, text: text}), do: qualitative(text)
  defp reading_load(_none), do: nil

  defp numeric_load(value, value_max, unit, text) do
    %{
      kind: if(unit in ["%", "pct"], do: "pct_1rm", else: "kg"),
      value: decimal(value),
      value_max: value_max && decimal(value_max),
      text: text
    }
  end

  defp qualitative(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> %{kind: "qualitative", value: nil, value_max: nil, text: trimmed}
    end
  end

  defp qualitative(_text), do: nil

  defp compact_load(%{kind: "bw"}, _i),
    do: %{kind: "bodyweight", value: nil, value_max: nil, text: nil}

  defp compact_load(%{kind: kind, entries: [_ | _] = entries} = load, i)
       when kind in ["kg", "pct"] do
    entry = Enum.at(entries, i) || List.last(entries)
    value_max = if entry.max != entry.min, do: entry.max
    numeric_load(entry.min, value_max, kind, if(load.up, do: "up"))
  end

  defp compact_load(%{kind: "text", text: text}, _i), do: qualitative(text)
  defp compact_load(_load, _i), do: nil

  # ── measures ─────────────────────────────────────────

  defp measure_column(row, "tempo", n),
    do: row |> Notation.repeat_text("tempo", n) |> Enum.map(&Notation.tempo_parts/1)

  defp measure_column(row, key, n) do
    clock? = Catalog.measure(key).clock

    row
    |> Notation.progress_readings(key, n, clock?)
    |> Enum.map(fn
      %{value: value, suffix: suffix} -> canonical_number(key, value, suffix)
      _text_or_nil -> nil
    end)
  end

  defp measures_at(values, i) do
    Enum.reduce(values, empty_measures(), fn {key, column}, acc ->
      put_measure(acc, key, Enum.at(column, i))
    end)
  end

  defp empty_measures do
    %{
      pace_secs_per_500m: nil,
      tempo: nil,
      rpe: nil,
      rir: nil,
      hr_zone: nil,
      height_cm: nil,
      distance_m: nil,
      hold_secs: nil
    }
  end

  defp put_measure(acc, _key, nil), do: acc
  defp put_measure(acc, key, value), do: Map.put(acc, measure_field(key), value)

  defp measure_field("pace"), do: :pace_secs_per_500m
  defp measure_field("tempo"), do: :tempo
  defp measure_field("rpe"), do: :rpe
  defp measure_field("rir"), do: :rir
  defp measure_field("zone"), do: :hr_zone
  defp measure_field("height"), do: :height_cm
  defp measure_field("dist"), do: :distance_m
  defp measure_field("hold"), do: :hold_secs

  # One typed value ("2:00", "31X1", "z2", "1.2 m", "2 km") in canonical
  # units, read as one column of the editor.
  defp canonical(key, text) when key in @measure_keys and is_binary(text),
    do: %{"cells" => [%{key => text}]} |> measure_column(key, 1) |> hd()

  defp canonical(_key, _text), do: nil

  defp canonical_number("pace", secs, suffix) do
    suffix = String.downcase(suffix)

    cond do
      String.contains?(suffix, "km") -> round_number(secs / 2)
      String.contains?(suffix, "100") -> round_number(secs * 5)
      String.contains?(suffix, "mi") -> round_number(secs * 500 / 1609.344)
      true -> round_number(secs)
    end
  end

  defp canonical_number("zone", value, _suffix), do: trunc(value)

  defp canonical_number("height", value, suffix) do
    suffix = String.downcase(String.trim(suffix))
    if suffix in ["m", "μ"], do: round_number(value * 100), else: round_number(value)
  end

  defp canonical_number("dist", value, suffix) do
    if String.contains?(String.downcase(suffix), "km"),
      do: round_number(value * 1000),
      else: round_number(value)
  end

  defp canonical_number("hold", value, suffix) do
    if Regex.match?(~r/^\s*(min|'|′|λ)/u, suffix),
      do: round_number(value * 60),
      else: round_number(value)
  end

  defp canonical_number(_key, value, _suffix), do: round_number(value)

  # ── structure ────────────────────────────────────────

  defp structure(%{"kind" => kind} = struct) do
    %{
      kind: kind,
      clusters: count(struct["clusters"]),
      intra_secs: seconds(struct["intra"], :smart),
      drops: count(struct["drops"]),
      drop_by: blank_to_nil(struct["dropby"]),
      minis: count(struct["minis"])
    }
  end

  defp structure(_struct), do: nil

  # ── helpers ──────────────────────────────────────────

  defp round_number(value) when is_integer(value), do: value

  defp round_number(value) when is_float(value) do
    rounded = Float.round(value, 2)
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  defp decimal(value) when is_integer(value), do: Decimal.new(value)

  defp decimal(value) when is_float(value) do
    rounded = Float.round(value, 2)

    if rounded == trunc(rounded),
      do: Decimal.new(trunc(rounded)),
      else: Decimal.from_float(rounded)
  end

  defp list(map, key) do
    case Map.get(map, key) do
      list when is_list(list) -> list
      _none -> []
    end
  end

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: String.trim(value)
  end

  defp blank_to_nil(_value), do: nil
end
