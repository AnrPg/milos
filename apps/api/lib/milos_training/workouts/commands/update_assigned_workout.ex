defmodule MilosTraining.Workouts.Commands.UpdateAssignedWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id, params) do
    params
    |> normalize()
    |> then(&WorkoutStore.update_assigned_workout(id, &1))
  end

  defp normalize(params) do
    athlete_ids =
      params
      |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
      |> List.wrap()
      |> Enum.reject(&blank?/1)
      |> Enum.uniq()

    params
    |> Map.put(:athlete_ids, athlete_ids)
    |> Map.delete("athlete_ids")
  end

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
end
