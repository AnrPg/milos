defmodule MilosTraining.Application.AssignWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Workouts}

  def call(params) do
    athlete_ids =
      params
      |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
      |> List.wrap()
      |> Enum.uniq()

    athletes = Identity.list_by_ids(athlete_ids)

    if valid_athletes?(athlete_ids, athletes) do
      with {:ok, assignment} <- Workouts.assign_workout(params) do
        broadcast_assignment_refresh(assignment)
        {:ok, assignment}
      end
    else
      {:error, :invalid_athletes}
    end
  end

  defp valid_athletes?(athlete_ids, athletes) do
    MapSet.new(athlete_ids) == MapSet.new(Enum.map(athletes, & &1.id)) and
      Enum.all?(athletes, &(&1.role == :athlete))
  end

  defp broadcast_assignment_refresh(assignment) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(
      (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids,
      ["assigned_workouts"],
      reason: "assignment_created",
      payload: %{assignment_id: assignment.id}
    )
  end
end
