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
  * the first column's reps and load where they are whole numbers
    (`prescription_value`/`prescription_unit`, `load_value`/`load_mode`),
    the sets of a `sets` flow (or of a dose like "4×10"), the tempo, the
    `exercise_ref` and the note.
  """

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.Notation

  @mode "structured_plan"
  @group_namespace "palee:structured-plan:group:"
  @dose_units %{reps: "reps", secs: "secs", kcal: "kcal", m: "meters"}

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
  defp put_plan(section, plan) do
    exercises = exercises(plan)

    if Enum.any?(Map.keys(section), &is_atom/1) do
      section
      |> Map.drop([:sections, :exercises, :plan])
      |> Map.merge(%{plan: plan, exercises: Enum.map(exercises, &atom_keys/1)})
    else
      section
      |> Map.drop(["sections", "exercises", "plan"])
      |> Map.merge(%{"plan" => plan, "exercises" => exercises})
    end
  end

  # Only the materialiser's own fixed keys are turned into atoms.
  defp atom_keys(exercise),
    do: Map.new(exercise, fn {key, item} -> {String.to_existing_atom(key), item} end)

  @doc "The legacy exercise rows of a (valid) plan, as `workout_exercises` params."
  @spec exercises(map()) :: [map()]
  def exercises(%{} = plan) do
    blocks = plan |> Map.get("blocks", []) |> List.wrap()
    interrupt = plan |> Map.get("interrupt") |> List.wrap()
    flow = Map.get(plan, "flow")
    sets = if flow == "sets", do: Notation.max_count(get_in(plan, ["params", "sets"]))

    (blocks ++ [interrupt])
    |> Enum.flat_map(&StructuredPlan.units/1)
    |> Enum.flat_map(fn unit ->
      rows = Enum.filter(unit.rows, &exercise_row?/1)
      group = if length(rows) > 1, do: group_uuid(unit.group)
      Enum.map(rows, &exercise(&1, flow, sets, group))
    end)
  end

  defp exercise_row?(row),
    do: Map.get(row, "kind") == "ex" and String.trim(Map.get(row, "name") || "") != ""

  defp exercise(row, flow, sets, group) do
    first = first_cell(row, flow)
    dose = Notation.parse_dose(first_value(first, row, "d", "dose"))
    load = first_load(row, first)

    %{
      "item_type" => "exercise",
      "name" => String.trim(row["name"]),
      "exercise_ref" => blank_to_nil(row["exerciseRef"]),
      "note" => blank_to_nil(row["note"]),
      "tempo" =>
        blank_to_nil(first_value(first, row, "tempo", nil) || get_in(row, ["x", "tempo"])),
      "superset_group_id" => group,
      "sets" => sets || dose_sets(dose)
    }
    |> Map.merge(prescription(dose))
    |> Map.merge(load)
  end

  # Per set (flow `sets`) or per round, the first column holds the values;
  # otherwise the row's same-every-time values do.
  defp first_cell(row, flow) do
    if flow == "sets" or row["perRound"] == true do
      case row["cells"] do
        [%{} = cell | _rest] -> cell
        _none -> %{}
      end
    end
  end

  defp first_value(nil, row, _cell_key, row_key) when is_binary(row_key), do: row[row_key]
  defp first_value(nil, _row, _cell_key, nil), do: nil

  defp first_value(cell, row, cell_key, row_key) do
    case cell[cell_key] do
      value when is_binary(value) and value != "" -> value
      _empty -> if row_key, do: row[row_key]
    end
  end

  defp prescription(%{max: nil, entries: [%{min: same, max: same}], unit: unit}) do
    case whole(same) do
      nil -> %{}
      number -> %{"prescription_value" => number, "prescription_unit" => @dose_units[unit]}
    end
  end

  defp prescription(_dose), do: %{}

  defp dose_sets(%{sets: %{max: max}}), do: max
  defp dose_sets(_dose), do: nil

  defp first_load(row, first) do
    loads =
      if first,
        do: Enum.map(List.wrap(row["cells"]), &cell_load/1),
        else: [row["load"]]

    %{unit: unit} = Notation.row_load_issues(loads)
    text = first_value(first, row, "l", "load")

    case Notation.first_load(text, unit) do
      %{mode: :bw} ->
        %{"load_mode" => "bw"}

      %{value: number, mode: mode} ->
        case whole(number) do
          nil -> %{}
          number -> %{"load_value" => number, "load_mode" => Atom.to_string(mode)}
        end

      nil ->
        %{}
    end
  end

  defp cell_load(%{"l" => load}), do: load
  defp cell_load(_cell), do: nil

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

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  defp blank_to_nil(_value), do: nil

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
