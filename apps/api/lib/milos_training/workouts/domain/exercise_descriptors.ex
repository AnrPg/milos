defmodule MilosTraining.Workouts.Domain.ExerciseDescriptors do
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

  alias MilosTraining.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  def from_workout(%{sections: sections}) when is_list(sections) do
    sections
    |> Enum.flat_map(&(field(&1, :exercises) || []))
    |> Enum.reject(&(to_string(field(&1, :item_type) || "exercise") == "header"))
    |> Enum.reject(&(field(&1, :excluded) == true))
    |> Enum.filter(&is_binary(field(&1, :name)))
    |> Enum.map(&descriptor/1)
  end

  def from_workout(_workout), do: []

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
