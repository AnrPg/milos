defmodule MilosTraining.Workouts.Domain.WorkoutAuthoring do
  @moduledoc """
  Pure authoring helpers for workout payload normalization.

  Phase 2 authoring is linear, so section and exercise order are derived from
  list position rather than trusted from caller-supplied integers.
  """

  def normalize_structure(params) when is_map(params) do
    sections =
      params
      |> get_sections()
      |> Enum.with_index(1)
      |> Enum.map(fn {section, index} -> normalize_section(section, index) end)

    params
    |> drop_key(:sections)
    |> drop_key("sections")
    |> Map.put(:sections, sections)
  end

  defp normalize_section(section, order) do
    exercises =
      section
      |> get_exercises()
      |> Enum.with_index(1)
      |> Enum.map(fn {exercise, index} -> normalize_exercise(exercise, index) end)

    section
    |> drop_key(:order)
    |> drop_key("order")
    |> drop_key(:exercises)
    |> drop_key("exercises")
    |> Map.put(:order, order)
    |> Map.put(:exercises, exercises)
  end

  defp normalize_exercise(exercise, order) do
    exercise
    |> drop_key(:order)
    |> drop_key("order")
    |> Map.put(:order, order)
  end

  defp get_sections(params), do: Map.get(params, :sections) || Map.get(params, "sections") || []

  defp get_exercises(section),
    do: Map.get(section, :exercises) || Map.get(section, "exercises") || []

  defp drop_key(map, key), do: Map.delete(map, key)
end
