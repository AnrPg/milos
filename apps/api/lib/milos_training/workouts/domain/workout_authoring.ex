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
      |> Enum.map(fn {section, index} -> normalize_section(section, index, nil) end)

    params
    |> drop_key(:sections)
    |> drop_key("sections")
    |> Map.put(:sections, sections)
  end

  defp normalize_section(section, order, parent_section_id) do
    exercises =
      section
      |> get_exercises()
      |> Enum.with_index(1)
      |> Enum.map(fn {exercise, index} -> normalize_exercise(exercise, index) end)

    child_sections =
      section
      |> get_sections()
      |> Enum.with_index(1)
      |> Enum.map(fn {child_section, index} ->
        # child sections track their parent by the parent's id or localId (client-assigned temp id)
        normalize_section(child_section, index, parent_section_id_from(section))
      end)

    normalized =
      section
      |> drop_key(:order)
      |> drop_key("order")
      |> drop_key(:exercises)
      |> drop_key("exercises")
      |> drop_key(:sections)
      |> drop_key("sections")
      |> maybe_put(:parent_section_id, parent_section_id)
      |> Map.put(:order, order)
      |> Map.put(:exercises, exercises)

    if child_sections == [] do
      normalized
    else
      Map.put(normalized, :sections, child_sections)
    end
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

  defp parent_section_id_from(section),
    do:
      Map.get(section, :id) || Map.get(section, "id") || Map.get(section, :localId) ||
        Map.get(section, "localId")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp drop_key(map, key), do: Map.delete(map, key)
end
