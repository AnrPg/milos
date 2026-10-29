defmodule Palee.Workouts.Domain.PlanWorkload do
  @moduledoc """
  What a structured plan section (ADR-270) means for the consumers that count
  training: sets, reps, volume (kg × reps), calories, distance and work time,
  per exercise row and for the section, and the section's time domain. Pure.

  It reads the plan through its canonical read model
  (`StructuredPlan.Prescription`), never the text, and the athlete's actuals
  (`execution_plan_sets`, one record per set / round / part) when there are
  any:

  * **actuals** — a section with at least one record is counted from them:
    one set per place (round, phase) of a row, its reps and kg as the
    athlete did them (the web runner already fills an unlogged set with the
    prescription). A value the record lacks (a rep range, "max", a load in %
    without a known 1RM, distances and calories, which the runner sends as
    text) comes from the row's prescription for that round. Open-ended
    sections (AMRAP, EMOM until failure) therefore count what was done.
  * **prescription** — otherwise every set the plan prescribes, round by
    round: a `sets` flow of "3-4" sets counts the optional round as half a
    set (the midpoint); same-every-time rows count once per round they apply
    to; an open-ended section counts the rounds the athlete scored
    (`rounds_done`, from an AMRAP's "5+3") with the plan's own rule after the
    written rounds (repeat, or keep stepping by the "+x" the coach wrote),
    and only the written rounds when no score is known; interruption rows
    count once per interruption that fits in the known time.

  Volume counts reps (unit `reps`) × kg. Loads: kg as written; a % of 1RM
  becomes kg when the athlete's 1RM is known (`one_rep_max`); bodyweight and
  words carry no kg. A range (8-12 reps, 60-70 kg, 3-4 sets) uses its
  midpoint and marks the result `estimated`; so does an open-ended section
  without actuals or score. Clusters and rest-pause repeat the set's reps per
  part, a drop set does them again at a load lowered by `dropby` ("20%",
  "10kg"); "4×10" inside a row of a flow other than `sets` is four sets of
  10; a row marked per side counts both sides.
  """

  alias Palee.Workouts.Domain.StructuredPlan.Prescription

  @zero Decimal.new(0)
  @one Decimal.new(1)
  @half Decimal.new("0.5")
  @hundred Decimal.new(100)
  # Rounds counted for an open-ended section, whatever a score claims.
  @max_rounds 500

  @type one_rep_max :: (String.t() | nil, String.t() | nil -> number() | Decimal.t() | nil)

  @type row_workload :: %{
          row_id: String.t(),
          name: String.t() | nil,
          exercise_ref: String.t() | nil,
          block_index: integer(),
          interrupt: boolean(),
          group_id: String.t() | nil,
          per_side: boolean(),
          sets: number(),
          logged_sets: non_neg_integer(),
          reps: number(),
          volume_kg: number(),
          calories: number(),
          distance_m: number(),
          work_secs: number(),
          top_set: %{load_kg: number(), reps: number() | nil} | nil,
          estimated: boolean()
        }

  @doc """
  The workload of one plan section (see the module doc), or nil for anything
  that is not a valid plan. `actuals` are the athlete's records of this
  section (maps with atom or string keys, numbers or `Decimal`s).

  Options: `:one_rep_max` (`fn name, exercise_ref -> kg | nil end`),
  `:rounds_done` (full rounds of an open-ended section, e.g. from its score)
  and `:elapsed_secs` (time spent in the section, for interruptions).
  """
  @spec section(term(), [map()], keyword()) :: map() | nil
  def section(plan, actuals \\ [], opts \\ []) do
    case Prescription.build(plan) do
      nil -> nil
      %{clock: clock, rows: rows} -> section_workload(clock, rows, List.wrap(actuals), opts)
    end
  end

  defp section_workload(clock, rows, actuals, opts) do
    exercise_rows = Enum.filter(rows, &(&1.kind == "exercise"))

    {source, workloads} =
      case actuals do
        [] -> {"prescription", Enum.map(exercise_rows, &prescribed_row(&1, clock, opts))}
        records -> {"actuals", actual_rows(exercise_rows, clock, records, opts)}
      end

    workloads = Enum.reject(workloads, &Decimal.equal?(&1.sets, 0))

    %{
      flow: clock.flow,
      score: clock.score,
      preset: clock.preset,
      open_ended: clock.open_ended,
      source: source,
      time_domain: time_domain(clock),
      exercises: Enum.map(workloads, &output_row/1),
      totals: workloads |> totals_of() |> output_totals()
    }
  end

  @doc """
  How many sets each exercise row of a plan is done in, as prescribed (one
  per round it applies to, at least 1): the weight goal suggestion and
  coverage give each exercise. `%{row_id, name, exercise_ref, sets}`.
  """
  @spec exercise_weights(term()) :: [map()]
  def exercise_weights(plan) do
    case Prescription.build(plan) do
      nil ->
        []

      %{clock: clock, rows: rows} ->
        rows
        |> Enum.filter(&(&1.kind == "exercise" and is_binary(&1.name)))
        |> Enum.map(fn row ->
          workload = prescribed_row(row, clock, [])

          %{
            row_id: row.row_id,
            name: row.name,
            exercise_ref: row.exercise_ref,
            sets: workload.sets |> Decimal.round(0, :half_up) |> Decimal.to_integer() |> max(1)
          }
        end)
    end
  end

  @doc """
  A section's time domain in seconds, from its clock: `planned_secs` (how
  long it runs when that is fixed: AMRAP windows and the rests between them,
  EMOM minutes, intervals, rest), `cap_secs` (a For Time cap) and whether it
  is `open_ended`. A `sets` flow has no clock of its own.
  """
  @spec time_domain(map()) :: %{
          planned_secs: pos_integer() | nil,
          cap_secs: pos_integer() | nil,
          open_ended: boolean()
        }
  def time_domain(clock) do
    %{
      planned_secs: planned_secs(clock),
      cap_secs: clock[:cap_secs],
      open_ended: clock[:open_ended] == true
    }
  end

  defp planned_secs(%{flow: "amrap", windows_secs: [_ | _] = windows} = clock) do
    rest = (clock.rest_secs && clock.rest_secs.min) || 0
    Enum.sum(windows) + rest * (length(windows) - 1)
  end

  defp planned_secs(%{flow: "emom", every_secs: every, times: times})
       when is_integer(every) and is_integer(times),
       do: every * times

  defp planned_secs(%{flow: "intervals", work_secs: work, rounds: rounds} = clock)
       when is_integer(work) and is_integer(rounds) do
    case clock.off_secs do
      off when is_integer(off) -> (work + off) * rounds - off
      nil when clock.hr_target_bpm != nil -> nil
      nil -> work * rounds
    end
  end

  defp planned_secs(%{flow: "rest", dur_secs: secs}) when is_integer(secs), do: secs
  defp planned_secs(_clock), do: nil

  @doc """
  Full rounds of an open-ended section from its score: "5+3" (rounds +
  reps) and a plain number of rounds give 5; anything else nil.
  """
  @spec rounds_from_score(term()) :: non_neg_integer() | nil
  def rounds_from_score(value) when is_integer(value) and value >= 0, do: value

  def rounds_from_score(value) when is_float(value) and value >= 0, do: trunc(value)

  def rounds_from_score(value) when is_binary(value) do
    case Regex.run(~r/^\s*(\d+)\s*(?:\+\s*\d+)?\s*$/, value) do
      [_all, rounds] -> String.to_integer(rounds)
      nil -> nil
    end
  end

  def rounds_from_score(_value), do: nil

  @doc """
  Sums section workloads (as `section/3` returns them) into one total and
  one entry per exercise (same catalog ref, else same name).
  """
  @spec merge([map() | nil]) :: %{totals: map(), exercises: [map()]}
  def merge(sections) do
    sections = Enum.reject(sections, &is_nil/1)
    rows = Enum.flat_map(sections, & &1.exercises)

    exercises =
      rows
      |> Enum.group_by(&exercise_key/1)
      |> Enum.map(fn {_key, [first | _rest] = same} ->
        %{
          name: first.name,
          exercise_ref: first.exercise_ref,
          sets: sum_number(same, :sets),
          logged_sets: sum_number(same, :logged_sets),
          reps: sum_number(same, :reps),
          volume_kg: sum_number(same, :volume_kg),
          calories: sum_number(same, :calories),
          distance_m: sum_number(same, :distance_m),
          work_secs: sum_number(same, :work_secs),
          top_set: same |> Enum.map(& &1.top_set) |> best_top_set(),
          estimated: Enum.any?(same, & &1.estimated)
        }
      end)
      |> Enum.sort_by(&{-&1.volume_kg, -&1.sets, &1.name || ""})

    totals =
      Enum.reduce(
        ~w(sets logged_sets reps volume_kg calories distance_m work_secs)a,
        %{estimated: Enum.any?(sections, & &1.totals.estimated)},
        fn key, acc -> Map.put(acc, key, sum_number(Enum.map(sections, & &1.totals), key)) end
      )

    %{totals: totals, exercises: exercises}
  end

  defp exercise_key(%{exercise_ref: ref}) when is_binary(ref), do: {:ref, ref}

  defp exercise_key(%{name: name}) when is_binary(name),
    do: {:name, name |> String.trim() |> String.downcase()}

  defp exercise_key(row), do: {:row, row.row_id}

  defp sum_number(maps, key) do
    maps
    |> Enum.map(&Map.get(&1, key, 0))
    |> Enum.reduce(@zero, fn value, acc -> Decimal.add(acc, to_decimal(value) || @zero) end)
    |> number()
  end

  defp best_top_set(top_sets) do
    top_sets
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&{&1.load_kg, &1.reps || 0}, fn -> nil end)
  end

  # ── prescription ─────────────────────────────────────

  defp prescribed_row(row, clock, opts) do
    one_rep_max = one_rep_max(row, opts)

    row
    |> occurrences(clock, opts)
    |> Enum.reduce(empty(row), fn {set, weight, estimated?}, acc ->
      acc
      |> add_sets(Decimal.mult(weight, dose_sets(set, clock)))
      |> add_parts(row, set, weight, one_rep_max, clock)
      |> estimate(estimated? or dose_sets_range?(set, clock))
    end)
  end

  # {set, weight, estimated?} for every time the row is done as prescribed.
  defp occurrences(%{interrupt: true} = row, clock, opts) do
    {count, estimated?} = interruptions(clock, opts)

    case row.sets do
      [set | _rest] when count > 0 ->
        List.duplicate({set, @one, estimated?}, count)

      _none ->
        []
    end
  end

  defp occurrences(row, %{open_ended: true} = clock, opts) do
    case Keyword.get(opts, :rounds_done) do
      rounds when is_integer(rounds) and rounds >= 0 ->
        k = max(clock.blocks, 1)

        1..min(rounds, @max_rounds)//1
        |> Enum.filter(&(rem(&1 - 1, k) == row.block_index))
        |> Enum.flat_map(fn round ->
          case open_set(row, div(round - 1, k)) do
            nil -> []
            set -> [{set, @one, false}]
          end
        end)

      _unknown ->
        Enum.map(row.sets, &{&1, @one, true})
    end
  end

  defp occurrences(row, clock, _opts) do
    Enum.flat_map(row.sets, fn set ->
      Enum.map(set.rounds, &{set, round_weight(clock, &1), optional_round?(clock, &1)})
    end)
  end

  # A `sets` flow of "3-4": the 4th set is optional, half a set at the midpoint.
  defp round_weight(clock, round), do: if(optional_round?(clock, round), do: @half, else: @one)

  defp optional_round?(%{flow: "sets", sets: %{min: min}}, round), do: round > min
  defp optional_round?(_clock, _round), do: false

  # Column `i` (0-based) of an open-ended row: written, or past the written
  # ones by the row's rule.
  defp open_set(%{sets: []}, _i), do: nil

  defp open_set(%{sets: sets} = row, i) do
    written = length(sets)

    if i < written,
      do: Enum.at(sets, i),
      else: step_set(List.last(sets), row.then, i - written + 1)
  end

  defp step_set(set, %{rule: "step"} = rule, n) do
    %{
      set
      | reps: step_reps(set.reps, rule.reps_step, n),
        load: step_load(set.load, rule.load_step, n)
    }
  end

  defp step_set(set, _rule, _n), do: set

  defp step_reps(%{min: min, max: max} = reps, step, n)
       when is_number(step) and is_number(min) and is_number(max),
       do: %{reps | min: max(min + step * n, 0), max: max(max + step * n, 0)}

  defp step_reps(reps, _step, _n), do: reps

  defp step_load(%{value: %Decimal{} = value} = load, %Decimal{} = step, n) do
    shift = Decimal.mult(step, n)

    %{
      load
      | value: Decimal.add(value, shift),
        value_max: load.value_max && Decimal.add(load.value_max, shift)
    }
  end

  defp step_load(load, _step, _n), do: load

  # How many times the interruption fires: in the time spent in the section
  # when known, else in the time the clock fixes (or its cap, estimated).
  defp interruptions(%{interrupt_every_secs: every} = clock, opts)
       when is_integer(every) and every > 0 do
    case Keyword.get(opts, :elapsed_secs) do
      secs when is_integer(secs) and secs >= 0 ->
        {div(secs, every), false}

      _unknown ->
        case planned_secs(clock) || clock.cap_secs do
          secs when is_integer(secs) -> {div(secs, every), is_nil(planned_secs(clock))}
          nil -> {0, true}
        end
    end
  end

  defp interruptions(_clock, _opts), do: {0, false}

  # "4×10" in a row of a flow other than `sets`: four sets each time.
  defp dose_sets(%{reps: %{sets: %{min: min, max: max}}}, %{flow: flow}) when flow != "sets",
    do: midpoint(Decimal.new(min), Decimal.new(max))

  defp dose_sets(_set, _clock), do: @one

  defp dose_sets_range?(%{reps: %{sets: %{min: min, max: max}}}, %{flow: flow})
       when flow != "sets",
       do: min != max

  defp dose_sets_range?(_set, _clock), do: false

  # The parts of one set (cluster pieces, drops, rest-pause minis), each
  # with the set's reps; a drop lowers the load.
  defp add_parts(acc, row, set, weight, one_rep_max, clock) do
    times = Decimal.mult(weight, dose_sets(set, clock))
    {reps, reps_estimated?} = reps_value(set.reps)
    {kg, kg_estimated?} = load_kg(set.load, one_rep_max)

    row
    |> parts(kg)
    |> Enum.reduce(acc, fn part_kg, acc ->
      add_quantity(acc, row, unit(set.reps), reps, part_kg, times)
    end)
    |> estimate(reps_estimated? or kg_estimated?)
  end

  defp parts(%{structure: %{kind: kind} = structure}, kg) when kind in ["cluster", "restpause"] do
    count = (kind == "cluster" && structure.clusters) || (kind == "restpause" && structure.minis)
    List.duplicate(kg, max(count || 1, 1))
  end

  defp parts(%{structure: %{kind: "drop"} = structure}, kg) do
    drops = max(structure.drops || 1, 1)

    Enum.map(0..drops, fn i -> kg && dropped(kg, structure.drop_by, i) end)
  end

  defp parts(_row, kg), do: [kg]

  defp dropped(kg, _by, 0), do: kg

  defp dropped(kg, by, i) do
    case by && Regex.run(~r/^\s*-?\s*(\d+(?:[.,]\d+)?)\s*(%|kg)?\s*$/iu, by) do
      [_all, amount, "%"] ->
        factor = Decimal.sub(@one, Decimal.div(decimal_text(amount), @hundred))
        1..i |> Enum.reduce(kg, fn _drop, acc -> Decimal.mult(acc, factor) end) |> non_negative()

      [_all, amount | _unit] ->
        kg |> Decimal.sub(Decimal.mult(decimal_text(amount), i)) |> non_negative()

      _unknown ->
        kg
    end
  end

  defp non_negative(decimal), do: Decimal.max(decimal, @zero) |> Decimal.round(2)

  defp decimal_text(text), do: text |> String.replace(",", ".") |> Decimal.new()

  # Reps of a prescription: the midpoint of a range (estimated); nil for max
  # effort.
  defp reps_value(%{max_effort: true}), do: {nil, true}

  defp reps_value(%{min: min, max: max}) when is_number(min) and is_number(max),
    do: {midpoint(to_decimal(min), to_decimal(max)), min != max}

  defp reps_value(_reps), do: {nil, false}

  defp unit(%{unit: unit}), do: unit
  defp unit(_reps), do: "reps"

  # kg of a prescribed load: as written (midpoint of a range), or a % of a
  # known 1RM; nil without a number.
  defp load_kg(%{kind: "kg", value: %Decimal{} = value, value_max: max}, _one_rep_max),
    do: range_kg(value, max)

  defp load_kg(%{kind: "pct_1rm", value: %Decimal{} = value, value_max: max}, one_rep_max) do
    case one_rep_max do
      %Decimal{} = orm ->
        {kg, estimated?} = range_kg(value, max)
        {kg |> Decimal.mult(orm) |> Decimal.div(@hundred) |> Decimal.round(2), estimated?}

      nil ->
        {nil, true}
    end
  end

  defp load_kg(_load, _one_rep_max), do: {nil, false}

  defp range_kg(value, nil), do: {value, false}
  defp range_kg(value, max), do: {midpoint(value, max), not Decimal.equal?(value, max)}

  defp add_quantity(acc, row, unit, reps, kg, times) do
    side = if row.per_side, do: Decimal.new(2), else: @one

    case reps do
      nil ->
        acc

      reps ->
        quantity = reps |> Decimal.mult(times) |> Decimal.mult(side)

        case unit do
          "reps" ->
            acc
            |> Map.update!(:reps, &Decimal.add(&1, quantity))
            |> add_volume(quantity, kg)
            |> top_set(kg, reps)

          "kcal" ->
            Map.update!(acc, :calories, &Decimal.add(&1, quantity))

          "meters" ->
            Map.update!(acc, :distance_m, &Decimal.add(&1, quantity))

          "secs" ->
            Map.update!(acc, :work_secs, &Decimal.add(&1, quantity))

          _other ->
            acc
        end
    end
  end

  defp add_volume(acc, _quantity, nil), do: acc

  defp add_volume(acc, quantity, kg),
    do: Map.update!(acc, :volume_kg, &Decimal.add(&1, Decimal.mult(quantity, kg)))

  # ── actuals ──────────────────────────────────────────

  defp actual_rows(exercise_rows, clock, records, opts) do
    by_row = Map.new(exercise_rows, &{&1.row_id, &1})

    records
    |> Enum.map(&record/1)
    |> Enum.reject(&is_nil(&1.row_id))
    |> Enum.group_by(& &1.row_id)
    |> Enum.map(fn {row_id, row_records} ->
      row = Map.get(by_row, row_id) || orphan_row(row_id, hd(row_records))
      actual_row(row, clock, row_records, opts)
    end)
    |> Enum.sort_by(fn workload -> row_order(exercise_rows, workload.row_id) end)
  end

  defp row_order(rows, row_id),
    do: Enum.find_index(rows, &(&1.row_id == row_id)) || length(rows)

  # A record of a row the plan no longer has (edited after the run): only
  # what the record itself says.
  defp orphan_row(row_id, record) do
    %{
      row_id: row_id,
      kind: "exercise",
      name: record.exercise_name,
      exercise_ref: record.exercise_ref,
      block_index: record.block_index || 0,
      interrupt: record.interrupt,
      group_id: nil,
      per_side: false,
      structure: %{kind: "single"},
      sets: [],
      then: nil
    }
  end

  # The exercise as the athlete ran it (the runner names it as it showed it,
  # e.g. at their scale), else the plan row's.
  defp actual_row(row, clock, [first | _rest] = records, opts) do
    row = %{
      row
      | name: present(first.exercise_name) || row.name,
        exercise_ref: present(first.exercise_ref) || row.exercise_ref
    }

    one_rep_max = one_rep_max(row, opts)

    places =
      records
      |> Enum.group_by(&{&1.interrupt, &1.block_index, &1.round_index, &1.phase_index})

    logged = Enum.count(places, fn {_place, parts} -> Enum.any?(parts, & &1.logged) end)

    records
    |> Enum.reduce(empty(row), fn record, acc ->
      add_record(acc, row, clock, record, one_rep_max)
    end)
    |> Map.put(:sets, Decimal.new(map_size(places)))
    |> Map.put(:logged_sets, logged)
  end

  defp add_record(acc, row, clock, record, one_rep_max) do
    set = prescribed_set(row, clock, record)
    reps_unit = if set, do: unit(set.reps), else: "reps"

    {reps, reps_estimated?} =
      case record.actual_reps do
        %Decimal{} = reps -> {reps, false}
        nil -> if set, do: reps_value(set.reps), else: {nil, false}
      end

    {kg, kg_estimated?} = record_kg(record, set, one_rep_max)

    acc
    |> add_quantity(row, reps_unit, reps, kg, @one)
    |> estimate(reps_estimated? or kg_estimated?)
  end

  # The load the athlete lifted: logged, else prescribed in kg (or % × the
  # 1RM the runner used), else the prescription's own.
  defp record_kg(%{actual_load_kg: %Decimal{} = kg}, _set, _orm), do: {kg, false}
  defp record_kg(%{prescribed_load_kg: %Decimal{} = kg}, _set, _orm), do: {kg, false}

  defp record_kg(%{prescribed_load_pct: %Decimal{} = pct} = record, set, one_rep_max) do
    case record.one_rep_max_kg || one_rep_max do
      %Decimal{} = orm ->
        {pct |> Decimal.mult(orm) |> Decimal.div(@hundred) |> Decimal.round(2), false}

      nil ->
        if set, do: load_kg(set.load, nil), else: {nil, true}
    end
  end

  defp record_kg(_record, nil, _orm), do: {nil, false}
  defp record_kg(_record, set, one_rep_max), do: load_kg(set.load, one_rep_max)

  # The row's prescription for the round a record was done in.
  defp prescribed_set(%{sets: []}, _clock, _record), do: nil
  defp prescribed_set(%{interrupt: true, sets: [set | _rest]}, _clock, _record), do: set

  defp prescribed_set(row, %{open_ended: true} = clock, record) do
    k = max(clock.blocks, 1)
    open_set(row, div(max(record.round_index - 1, 0), k))
  end

  defp prescribed_set(row, _clock, record) do
    Enum.find(row.sets, &(record.round_index in &1.rounds)) || List.last(row.sets)
  end

  @record_numbers ~w(prescribed_reps prescribed_load_kg prescribed_load_pct one_rep_max_kg actual_reps actual_load_kg)a

  defp record(entry) do
    base = %{
      row_id: field(entry, :row_id),
      exercise_name: field(entry, :exercise_name),
      exercise_ref: field(entry, :exercise_ref),
      block_index: field(entry, :block_index),
      round_index: integer(field(entry, :round_index), 1),
      phase_index: integer(field(entry, :phase_index), 0),
      interrupt: field(entry, :interrupt) == true,
      logged: field(entry, :logged) == true
    }

    Enum.reduce(@record_numbers, base, fn key, acc ->
      Map.put(acc, key, positive_decimal(field(entry, key)))
    end)
  end

  defp integer(value, _default) when is_integer(value), do: value
  defp integer(_value, default), do: default

  defp positive_decimal(value) do
    case to_decimal(value) do
      %Decimal{} = decimal -> if Decimal.negative?(decimal), do: nil, else: decimal
      nil -> nil
    end
  end

  # ── accumulation ─────────────────────────────────────

  defp empty(row) do
    %{
      row_id: row.row_id,
      name: row.name,
      exercise_ref: row.exercise_ref,
      block_index: row.block_index,
      interrupt: row.interrupt,
      group_id: row.group_id,
      per_side: row.per_side,
      sets: @zero,
      logged_sets: 0,
      reps: @zero,
      volume_kg: @zero,
      calories: @zero,
      distance_m: @zero,
      work_secs: @zero,
      top_set: nil,
      estimated: false
    }
  end

  defp add_sets(acc, count), do: Map.update!(acc, :sets, &Decimal.add(&1, count))

  defp estimate(acc, true), do: %{acc | estimated: true}
  defp estimate(acc, false), do: acc

  defp top_set(acc, nil, _reps), do: acc

  defp top_set(%{top_set: nil} = acc, kg, reps), do: %{acc | top_set: %{load_kg: kg, reps: reps}}

  defp top_set(%{top_set: top} = acc, kg, reps) do
    if Decimal.gt?(kg, top.load_kg) or
         (Decimal.equal?(kg, top.load_kg) and Decimal.gt?(reps, top.reps)),
       do: %{acc | top_set: %{load_kg: kg, reps: reps}},
       else: acc
  end

  defp totals_of(workloads) do
    Enum.reduce(
      workloads,
      %{
        sets: @zero,
        logged_sets: 0,
        reps: @zero,
        volume_kg: @zero,
        calories: @zero,
        distance_m: @zero,
        work_secs: @zero,
        estimated: false
      },
      fn row, acc ->
        %{
          sets: Decimal.add(acc.sets, row.sets),
          logged_sets: acc.logged_sets + row.logged_sets,
          reps: Decimal.add(acc.reps, row.reps),
          volume_kg: Decimal.add(acc.volume_kg, row.volume_kg),
          calories: Decimal.add(acc.calories, row.calories),
          distance_m: Decimal.add(acc.distance_m, row.distance_m),
          work_secs: Decimal.add(acc.work_secs, row.work_secs),
          estimated: acc.estimated or row.estimated
        }
      end
    )
  end

  defp output_row(row) do
    %{
      row
      | sets: number(row.sets),
        reps: number(row.reps),
        volume_kg: number(row.volume_kg),
        calories: number(row.calories),
        distance_m: number(row.distance_m),
        work_secs: number(row.work_secs),
        top_set:
          row.top_set &&
            %{load_kg: number(row.top_set.load_kg), reps: number(row.top_set.reps)}
    }
  end

  defp output_totals(totals) do
    totals
    |> Map.new(fn
      {key, %Decimal{} = value} -> {key, number(value)}
      other -> other
    end)
  end

  # ── helpers ──────────────────────────────────────────

  defp one_rep_max(row, opts) do
    case Keyword.get(opts, :one_rep_max) do
      fun when is_function(fun, 2) -> positive_decimal(fun.(row.name, row.exercise_ref))
      _none -> nil
    end
  end

  defp present(text) when is_binary(text) do
    if String.trim(text) == "", do: nil, else: text
  end

  defp present(_text), do: nil

  defp midpoint(a, b), do: a |> Decimal.add(b) |> Decimal.div(2)

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp to_decimal(value) when is_float(value),
    do: value |> Decimal.from_float() |> Decimal.round(2)

  defp to_decimal(_value), do: nil

  defp number(nil), do: nil

  defp number(%Decimal{} = value) do
    value = value |> Decimal.round(2) |> Decimal.normalize()
    if Decimal.integer?(value), do: Decimal.to_integer(value), else: Decimal.to_float(value)
  end

  defp number(value) when is_number(value), do: value

  defp field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
