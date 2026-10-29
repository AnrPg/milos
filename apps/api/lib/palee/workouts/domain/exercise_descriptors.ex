defmodule Palee.Workouts.Domain.ExerciseDescriptors do
  @moduledoc """
  Reduces a normalized workout to the minimal exercise descriptors other
  contexts may reason about (ADR-124 injury warnings) without depending on
  Workouts internals: `%{name, exercise_ref, category}`.

  `exercise_ref` is the stable Quick Text catalog id. Structured workouts
  often carry no ref, so a canonical/alias name match against the catalog
  fills it in; anything else keeps `nil` and is left to the consumer's name
  heuristics. Headers are skipped.

  Scale-aware (TD-088): on a workout materialized for a scale level
  (`WorkoutMaterializer.materialize/2`), exercises the scale excludes are
  skipped, and an exercise whose applied variation overrides the name is a
  different movement - it is resolved by the override name, never by the
  base exercise's catalog ref.
  """

  alias Palee.Workouts.Domain.{FreeTextExercises, PlanWorkload}
  alias Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  def from_workout(%{sections: sections}) when is_list(sections) do
    sections
    |> Enum.flat_map(&(field(&1, :exercises) || []))
    |> Enum.reject(&(to_string(field(&1, :item_type) || "exercise") == "header"))
    |> Enum.reject(&(field(&1, :excluded) == true))
    |> Enum.filter(&is_binary(field(&1, :name)))
    |> Enum.map(&descriptor/1)
  end

  def from_workout(_workout), do: []

  @doc """
  Exercises of a workout with a weight, for WOD-goal suggestion (ADR-163):
  `%{name, exercise_ref, category, weight}`, where weight is the set count
  when the coach gave one, else 1.

  Structured and Quick Text workouts read their sections (a draft's sections
  come from its draft data); a structured plan section (ADR-270) weighs each
  exercise by the sets its plan prescribes. A free-text workout without sections is read
  line by line (`FreeTextExercises`). Names are resolved leniently (a plural
  such as "Thrusters" matches "Thruster"); an unresolved exercise keeps a
  `nil` ref so the caller can count it as unmatched.
  """
  def weighted_from_workout(workout) when is_map(workout) do
    case section_exercises(workout) do
      [] -> FreeTextExercises.from_text(free_text_body(workout))
      exercises -> Enum.map(exercises, &weighted_descriptor/1)
    end
  end

  def weighted_from_workout(_workout), do: []

  # A draft keeps its body in the draft data until it is published.
  defp free_text_body(workout),
    do: field(workout, :free_text_body) || field(field(workout, :draft_data), :free_text_body)

  defp section_exercises(workout) do
    (field(workout, :sections) || [])
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(&weighted_exercises/1)
    |> Enum.filter(&is_map/1)
    |> Enum.reject(&(to_string(field(&1, :item_type) || "exercise") == "header"))
    |> Enum.reject(&(field(&1, :excluded) == true))
    |> Enum.filter(&is_binary(field(&1, :name)))
  end

  # ADR-270: a plan section weighs each exercise by the sets its plan
  # prescribes (every round of an EMOM, the rounds of each block), which its
  # materialised rows cannot say.
  defp weighted_exercises(section) do
    case field(section, :plan) do
      %{} = plan -> PlanWorkload.exercise_weights(plan)
      _none -> field(section, :exercises) || []
    end
  end

  defp weighted_descriptor(exercise) do
    name = field(exercise, :name)

    entry =
      case base_ref(exercise) && ExerciseCatalog.fetch(base_ref(exercise)) do
        %{} = entry -> entry
        _missing -> FreeTextExercises.resolve_name(name)
      end

    %{
      name: name,
      exercise_ref: entry && entry.id,
      category: entry && entry.category,
      weight: weight(field(exercise, :sets))
    }
  end

  @doc """
  The catalog entry an exercise names, as `%{id, label, category}`: the
  given ref when it is a catalog id, else the name resolved leniently
  (plural-tolerant), else nil.
  """
  def resolve_catalog_entry(exercise_ref, name) do
    entry =
      case is_binary(exercise_ref) && ExerciseCatalog.fetch(exercise_ref) do
        %{} = entry -> entry
        _missing -> FreeTextExercises.resolve_name(name)
      end

    entry && %{id: entry.id, label: entry.label, category: entry.category}
  end

  defp weight(sets) when is_integer(sets) and sets > 0, do: sets
  defp weight(_sets), do: 1

  defp descriptor(exercise) do
    name = field(exercise, :name)
    entry = catalog_entry(base_ref(exercise), name)

    %{
      name: name,
      exercise_ref: entry && entry.id,
      category: entry && entry.category
    }
  end

  # A name override replaces the movement, so the base ref no longer applies.
  defp base_ref(exercise) do
    override = exercise |> field(:applied_variation) |> field(:exercise_name_override)
    if is_binary(override), do: nil, else: field(exercise, :exercise_ref)
  end

  defp catalog_entry(ref, name) do
    case ref && ExerciseCatalog.fetch(ref) do
      %{} = entry ->
        entry

      _missing ->
        case ExerciseCatalog.resolve(name) do
          {:ok, entry, _kind} -> entry
          {:error, _reason} -> nil
        end
    end
  end

  defp field(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key))
      value -> value
    end
  end

  defp field(_map, _key), do: nil
end
