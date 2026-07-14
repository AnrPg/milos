defmodule MilosTraining.Application.DeleteAssignedWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Workouts}

  def call(id) do
    assignment = Workouts.get_assigned_workout(id)

    with %{id: ^id} <- assignment,
         :ok <- Workouts.delete_assigned_workout(id) do
      broadcast_assignment_refresh(assignment)
      :ok
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_assignment_refresh(assignment) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(
      (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids,
      ["assigned_workouts"],
      reason: "assignment_deleted",
      payload: %{assignment_id: assignment.id}
    )
  end
end
