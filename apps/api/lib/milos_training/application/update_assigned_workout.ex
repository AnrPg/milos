defmodule MilosTraining.Application.UpdateAssignedWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Organizations, Workouts}

  def call(context, id, params) do
    update(context, id, params)
  end

  def call(_id, _params), do: {:error, :organization_context_required}

  defp update(context, id, params) do
    with :ok <- reject_workout_reassignment(params) do
      athlete_ids =
        params
        |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
        |> List.wrap()
        |> Enum.uniq()

      with {:ok, athletes} <- fetch_athletes(context, athlete_ids) do
        if valid_athletes?(context, athlete_ids, athletes) do
          previous_assignment = get_assigned_workout(context, id)

          with {:ok, assignment} <- update_assigned_workout(context, id, params) do
            broadcast_assignment_refresh(context, previous_assignment, assignment)
            {:ok, assignment}
          end
        else
          {:error, :invalid_athletes}
        end
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

  defp fetch_athletes(%{organization_id: organization_id}, athlete_ids) do
    valid? =
      Enum.all?(athlete_ids, fn user_id ->
        user_id
        |> Organizations.list_memberships()
        |> Enum.any?(fn %{membership: membership, organization: organization} ->
          organization.id == organization_id and membership.role == :athlete
        end)
      end)

    if valid?, do: {:ok, Identity.list_by_ids(athlete_ids)}, else: {:error, :invalid_athletes}
  end

  defp fetch_athletes(_context, _athlete_ids), do: {:error, :organization_context_required}

  defp valid_athletes?(_context, athlete_ids, athletes) do
    MapSet.new(athlete_ids) == MapSet.new(Enum.map(athletes, & &1.id))
  end

  defp broadcast_assignment_refresh(
         %{organization_id: organization_id},
         previous_assignment,
         assignment
       ) do
    admin_ids = Organizations.list_staff_user_ids(organization_id)

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

  defp get_assigned_workout(context, id), do: Workouts.get_assigned_workout(context, id)

  defp update_assigned_workout(context, id, params),
    do: Workouts.update_assigned_workout(context, id, params)
end
