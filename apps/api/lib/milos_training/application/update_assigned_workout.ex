defmodule MilosTraining.Application.UpdateAssignedWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Workouts}

  def call(id, params) do
    with :ok <- reject_workout_reassignment(params) do
      athlete_ids =
        params
        |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
        |> List.wrap()
        |> Enum.uniq()

      athletes = Identity.list_by_ids(athlete_ids)

      if valid_athletes?(athlete_ids, athletes) do
        previous_assignment = Workouts.get_assigned_workout(id)

        with {:ok, assignment} <- Workouts.update_assigned_workout(id, params) do
          broadcast_assignment_refresh(previous_assignment, assignment)
          {:ok, assignment}
        end
      else
        {:error, :invalid_athletes}
      end
    end
  end

  defp reject_workout_reassignment(params) do
    if Map.has_key?(params, :master_workout_id) or Map.has_key?(params, "master_workout_id") do
      {:error, :workout_reassignment_not_supported}
    else
      :ok
    end
  end

  defp valid_athletes?(athlete_ids, athletes) do
    MapSet.new(athlete_ids) == MapSet.new(Enum.map(athletes, & &1.id)) and
      Enum.all?(athletes, &(&1.role == :athlete))
  end

  defp broadcast_assignment_refresh(previous_assignment, assignment) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    user_ids =
      ((previous_assignment && Map.get(previous_assignment, :athlete_ids, [])) || []) ++
        (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids

    BroadcastUserSync.for_users(
      user_ids,
      ["assigned_workouts"],
      reason: "assignment_updated",
      payload: %{assignment_id: assignment.id}
    )
  end
end
