defmodule MilosTraining.Workouts.Domain.WorkoutMaterializer do
  @moduledoc """
  Pure domain module that derives scale-specific workout instances from a
  master workout by applying scale variations onto the base exercise values.
  """

  @doc "Returns scale levels that appear in at least one variation, ordered by sort_order."
  def available_scales(workout) do
    workout.sections
    |> Enum.flat_map(&Map.get(&1, :exercises, []))
    |> Enum.flat_map(&Map.get(&1, :variations, []))
    |> Enum.map(& &1.scale_level)
    |> Enum.reduce(%{}, fn scale_level, acc -> Map.put(acc, scale_level.slug, scale_level) end)
    |> Map.values()
    |> Enum.sort_by(&{&1.sort_order, &1.slug})
  end

  def materialize_all(workout) do
    scales = available_scales(workout)
    Enum.map(scales, fn scale_level -> materialize_with_scale(workout, scale_level) end)
  end

  @doc """
  Produces a scale-specific workout instance where exercises inherit the base
  values unless a variation exists for the requested scale.
  """
  def materialize(workout, scale_slug) do
    scale_level = Enum.find(available_scales(workout), &(&1.slug == scale_slug))
    materialize_with_scale(workout, scale_level)
  end

  defp materialize_with_scale(workout, scale_level) do
    sections =
      Enum.map(workout.sections, fn section ->
        exercises =
          Enum.map(section.exercises, fn exercise ->
            apply_variation(exercise, scale_level.slug)
          end)

        Map.put(section, :exercises, exercises)
      end)

    workout
    |> Map.put(:scale_level, scale_level)
    |> Map.put(:sections, sections)
  end

  defp apply_variation(exercise, scale_slug) do
    case Enum.find(exercise.variations, &(&1.scale_level.slug == scale_slug)) do
      nil ->
        exercise
        |> Map.put(:excluded, false)
        |> Map.put(:applied_variation, nil)

      %{excluded: true} = variation ->
        exercise
        |> Map.put(:excluded, true)
        |> Map.put(:applied_variation, variation)

      variation ->
        exercise
        |> maybe_put(:name, Map.get(variation, :exercise_name_override))
        |> maybe_put(:sets, Map.get(variation, :sets))
        |> maybe_put(:prescription_value, Map.get(variation, :prescription_value))
        |> maybe_put(:prescription_unit, Map.get(variation, :prescription_unit))
        |> maybe_put(:load_value, Map.get(variation, :load_value))
        |> maybe_put(:load_mode, Map.get(variation, :load_mode))
        |> Map.put(:excluded, false)
        |> Map.put(:applied_variation, variation)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
