defmodule Palee.Workouts.Domain.StructuredPlanWorkout do
  @moduledoc """
  Saving a workout written in the structured WOD editor (ADR-270), pure.

  A `structured_plan` workout keeps one plan per section
  (`workout_sections.plan`, see `StructuredPlan`), and the plan is the source
  of truth. History, analytics and exercise links still read the legacy
  `workout_exercises` rows, so on save every section's exercises are
  materialised from its plan and whatever exercises a client sent are
  ignored:

  * one exercise per exercise row with a name, in block and row order, then
    the interruption's rows; rest rows are not exercises;
  * rows of one group (a superset or complex of 2+ exercises) share a
    `superset_group_id`, a UUID derived from the group id, so it is the same
    on every save;
  * built from `StructuredPlan.Prescription`: `set_prescriptions` per set
    (a `sets` flow: one per round; other flows: one per distinct
    prescription), whole-number reps and loads in the integer columns
    (`prescription_value`/`prescription_unit`, `load_value`/`load_mode`,
    the first set's on the exercise), and in `metadata` what those columns
    cannot hold: decimal loads (`load_decimal`), rep ranges, max effort,
    words (`load_text`), the canonical measures and the rounds a set
    applies to (`plan_rounds`);
  * `prescription_metadata` keeps the plan row it came from
    (`plan_row_id`, `plan_block_index`, `plan_interrupt`), so actuals and
    analytics can join back to the plan; the tempo, `exercise_ref` and note.
  """

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.Prescription

  @mode "structured_plan"
  @group_namespace "palee:structured-plan:group:"

  def mode, do: @mode

  @doc "Whether workout params describe a structured plan workout."
  def plan?(%{} = params), do: to_string(value(params, :authoring_mode)) == @mode
  def plan?(_params), do: false

  @doc """
  Validates every section's plan and returns the params with each section's
  plan cleaned and its exercises materialised. The params keep their key
  style (atom or string `sections`).

  Errors: `{:error, :no_sections}` or `{:error, {:invalid_plan_sections, problems}}`,
  each problem `%{section: index_from_1, path: plan_path, code: code}`
  (`plan_required` when a section has no plan).
  """
  def prepare(%{} = params) do
    case value(params, :sections) do
      [_ | _] = sections ->
        sections
        |> Enum.with_index(1)
        |> Enum.map(fn {section, index} -> prepare_section(section, index) end)
        |> collect(params)

      _none ->
        {:error, :no_sections}
    end
  end

  defp collect(results, params) do
    case Enum.flat_map(results, fn
           {:error, problems} -> problems
           {:ok, _section} -> []
         end) do
      [] ->
        sections = Enum.map(results, fn {:ok, section} -> section end)
        key = if Map.has_key?(params, :sections), do: :sections, else: "sections"
        {:ok, params |> Map.delete(:sections) |> Map.delete("sections") |> Map.put(key, sections)}

      problems ->
        {:error, {:invalid_plan_sections, problems}}
    end
  end

  defp prepare_section(%{} = section, index) do
    case value(section, :plan) do
      %{} = plan ->
        case StructuredPlan.normalize(plan) do
          {:ok, plan} -> {:ok, put_plan(section, plan)}
          {:error, errors} -> {:error, Enum.map(errors, &Map.put(&1, :section, index))}
        end

      _none ->
        {:error, [%{section: index, path: "", code: "plan_required"}]}
    end
  end

  defp prepare_section(_section, index),
    do: {:error, [%{section: index, path: "", code: "plan_required"}]}

  # The section keeps its own key style (internal callers use atoms, requests
  # strings), so it still casts; the materialised exercises follow it.
  # The section's score is the plan's (`scoreable` / `score_config` like a
  # structured section), so leaderboards and PR detection read it as usual.
  defp put_plan(section, plan) do
    exercises = exercises(plan)
    score_config = StructuredPlan.score_config(plan)

    if Enum.any?(Map.keys(section), &is_atom/1) do
      section
      |> Map.drop([:sections, :exercises, :plan, :scoreable, :score_config])
      |> Map.merge(%{
        plan: plan,
        exercises: Enum.map(exercises, &atom_keys/1),
        scoreable: score_config != nil,
        score_config: score_config
      })
    else
      section
      |> Map.drop(["sections", "exercises", "plan", "scoreable", "score_config"])
      |> Map.merge(%{
        "plan" => plan,
        "exercises" => exercises,
        "scoreable" => score_config != nil,
        "score_config" => score_config
      })
    end
  end

  # Only the materialiser's own fixed keys are turned into atoms.
  defp atom_keys(exercise),
    do: Map.new(exercise, fn {key, item} -> {String.to_existing_atom(key), item} end)

  @doc "The legacy exercise rows of a (valid) plan, as `workout_exercises` params."
  @spec exercises(map()) :: [map()]
  def exercises(%{} = plan) do
    case Prescription.build(plan) do
      nil -> []
      %{clock: clock, rows: rows} -> materialise(clock, rows)
    end
  end

  defp materialise(clock, rows) do
    named = Enum.filter(rows, &(&1.kind == "exercise" and &1.name))

    # A superset id only for a group with 2+ exercises (rest rows do not count).
    sizes =
      named
      |> Enum.reject(&is_nil(&1.group_id))
      |> Enum.frequencies_by(&{&1.block_index, &1.group_id})

    Enum.map(named, fn row ->
      grouped? = row.group_id && Map.get(sizes, {row.block_index, row.group_id}, 0) > 1
      exercise(row, clock, if(grouped?, do: group_uuid(row.group_id)))
    end)
  end

  defp exercise(row, clock, group) do
    sets = legacy_sets(row, clock)
    first = List.first(sets)

    %{
      "item_type" => "exercise",
      "name" => row.name,
      "exercise_ref" => row.exercise_ref,
      "note" => row.note,
      "tempo" => first && tempo_text(first.measures.tempo),
      "superset_group_id" => group,
      "sets" => max(length(sets), 1),
      "set_prescriptions" => sets |> Enum.with_index(1) |> Enum.map(&set_prescription/1),
      "prescription_metadata" => exercise_metadata(row, first)
    }
    |> Map.merge(if(first, do: columns(first), else: %{}))
  end

  # The sets flow: one legacy set per round. Other flows: one per distinct
  # prescription (a same-every-time row is one set however many rounds).
  defp legacy_sets(row, %{flow: "sets"}) do
    Enum.flat_map(row.sets, fn set ->
      Enum.map(List.wrap(set.rounds), fn round -> %{set | rounds: [round]} end)
    end)
  end

  # "4×3" in a same-every-time row is four sets.
  defp legacy_sets(%{sets: [%{reps: %{sets: %{max: count}}} = set]}, _clock),
    do: List.duplicate(set, count)

  defp legacy_sets(row, _clock), do: row.sets

  defp set_prescription({set, index}) do
    set
    |> columns()
    |> Map.merge(%{"set_index" => index, "note" => nil, "metadata" => set_metadata(set)})
  end

  # Whole numbers go to the integer columns; the rest stays in metadata.
  defp columns(set) do
    reps =
      case set.reps do
        %{min: same, max: same, max_effort: false, unit: unit} ->
          case whole(same) do
            number when is_integer(number) and number >= 1 ->
              %{"prescription_value" => number, "prescription_unit" => unit}

            _other ->
              %{"prescription_unit" => unit}
          end

        %{unit: unit} ->
          %{"prescription_unit" => unit}

        nil ->
          %{}
      end

    Map.merge(reps, load_columns(set.load))
  end

  defp load_columns(%{kind: "bodyweight"}), do: %{"load_mode" => "bw"}

  defp load_columns(%{kind: kind, value: %Decimal{} = value}) when kind in ["kg", "pct_1rm"] do
    mode = if kind == "kg", do: "absolute", else: "pct_1rm"

    if Decimal.integer?(value),
      do: %{"load_value" => Decimal.to_integer(value), "load_mode" => mode},
      else: %{"load_mode" => mode}
  end

  defp load_columns(_load), do: %{}

  defp set_metadata(set) do
    reps = set.reps || %{}
    load = set.load || %{}
    measures = set.measures

    %{
      "load_unit" => load_unit(load[:kind]),
      "load_decimal" => decimal_number(load[:value]),
      "load_text" => load[:text],
      "reps_min" => if(reps[:min] != reps[:max], do: reps[:min]),
      "reps_max" => if(reps[:min] != reps[:max], do: reps[:max]),
      "max_effort" => if(reps[:max_effort], do: true),
      "within_seconds" => reps[:within_secs],
      "tempo" => tempo_text(measures.tempo),
      "target_rpe" => in_range(measures.rpe, 0, 10),
      "target_rir" => whole(measures.rir),
      "distance_meters" => positive(measures.distance_m),
      "hold_seconds" => measures.hold_secs,
      "pace_seconds_per_500m" => positive(measures.pace_secs_per_500m),
      "hr_zone" => in_range(measures.hr_zone, 1, 5),
      "height_cm" => positive(measures.height_cm),
      "rest_after_seconds" => set.rest_secs,
      "plan_rounds" => if(set.rounds != [], do: Enum.take(set.rounds, 500))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp exercise_metadata(row, first) do
    measures = if first, do: first.measures, else: %{}

    %{
      "plan_row_id" => row.row_id,
      "plan_block_index" => row.block_index,
      "plan_interrupt" => row.interrupt,
      "side" => if(row.per_side, do: "each"),
      "target_rpe" => in_range(measures[:rpe], 0, 10),
      "target_rir" => whole(measures[:rir]),
      "distance_meters" => positive(measures[:distance_m]),
      "height_cm" => positive(measures[:height_cm]),
      "hold_seconds" => measures[:hold_secs],
      "pace_seconds_per_500m" => positive(measures[:pace_secs_per_500m]),
      "hr_zone" => in_range(measures[:hr_zone], 1, 5)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp load_unit("kg"), do: "kg"
  defp load_unit("pct_1rm"), do: "pct_1rm"
  defp load_unit("bodyweight"), do: "bodyweight"
  defp load_unit(_kind), do: nil

  defp tempo_text(%{down: down, bottom: bottom, up: up, top: top}),
    do: Enum.map_join([down, bottom, up, top], "", &to_string/1)

  defp tempo_text(_tempo), do: nil

  defp decimal_number(%Decimal{} = value), do: Decimal.to_float(value)
  defp decimal_number(_value), do: nil

  defp in_range(value, min, max) when is_number(value) and value >= min and value <= max,
    do: value

  defp in_range(_value, _min, _max), do: nil

  defp positive(value) when is_number(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp whole(number) when is_integer(number) and number >= 0, do: number

  defp whole(number) when is_float(number) and number >= 0 do
    if number == Float.round(number), do: trunc(number)
  end

  defp whole(_number), do: nil

  @doc "A stable UUID for a plan group id, so a re-save keeps the same superset id."
  @spec group_uuid(String.t() | nil) :: String.t() | nil
  def group_uuid(nil), do: nil

  def group_uuid(group) when is_binary(group) do
    <<a::48, _version::4, b::12, _variant::2, c::62, _rest::binary>> =
      :crypto.hash(:sha256, @group_namespace <> group)

    <<a::48, 5::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> then(fn <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> ->
      Enum.join([p1, p2, p3, p4, p5], "-")
    end)
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
