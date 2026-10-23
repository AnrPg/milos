defmodule Palee.Application.DeleteAssignedWorkout do
  alias Palee.Application.{BroadcastUserSync, CoveringBranches, TrackAnalyticsEvent}
  alias Palee.{Organizations, Workouts}

  def call(context, id) do
    delete(context, id)
  end

  def call(_id), do: {:error, :organization_context_required}

  defp delete(context, id) do
    assignment = get_assigned_workout(context, id)

    with %{id: ^id} <- assignment,
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(assignment)),
         :ok <- delete_assigned_workout(context, id) do
      broadcast_assignment_refresh(context, assignment)
      TrackAnalyticsEvent.call("workout_assignment_deleted", context, assignment)
      :ok
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_assignment_refresh(%{organization_id: organization_id}, assignment) do
    admin_ids = Organizations.list_staff_user_ids(organization_id)

    BroadcastUserSync.for_users(
      (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids,
      ["assigned_workouts"],
      reason: "assignment_deleted",
      payload: %{assignment_id: assignment.id}
    )
  end

  defp get_assigned_workout(context, id), do: Workouts.get_assigned_workout(context, id)

  defp delete_assigned_workout(context, id), do: Workouts.delete_assigned_workout(context, id)
end
