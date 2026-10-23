defmodule Palee.Application.UpdateAssignedWorkout do
  @moduledoc """
  Edits an assignment's assignees, date and notes. ADR-125: assignees may be
  athletes or members (tenant membership roles); members newly added to the
  assignment need the explicit personal-programming grant, and a class variant
  keeps exactly one member who must still hold the class booking when the
  member is changed.
  """

  alias Palee.Application.{
    AuthorizeMemberProgramming,
    BroadcastUserSync,
    CoveringBranches,
    TenantAssigneeRoles
  }

  alias Palee.{Identity, Organizations, Scheduling, Workouts}
  alias Palee.Workouts.Domain.AssignmentAudiencePolicy

  def call(context, id, params) do
    update(context, id, params)
  end

  def call(_id, _params), do: {:error, :organization_context_required}

  defp update(%{organization_id: organization_id} = context, id, params)
       when is_binary(organization_id) do
    athlete_ids =
      params
      |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
      |> List.wrap()
      |> Enum.uniq()

    previous_assignment = get_assigned_workout(context, id)
    source_slot_id = previous_assignment && Map.get(previous_assignment, :source_slot_id)
    previous_ids = (previous_assignment && Map.get(previous_assignment, :athlete_ids)) || []

    with :ok <- authorize_branches(context, previous_assignment),
         {:ok, params} <- branch_params(context, params),
         :ok <- reject_workout_reassignment(params),
         {:ok, roles} <- TenantAssigneeRoles.call(context, athlete_ids),
         {:ok, classified} <- AssignmentAudiencePolicy.classify(athlete_ids, roles),
         :ok <- AssignmentAudiencePolicy.validate_class_variant(source_slot_id, classified),
         :ok <- variant_member_booked(context, source_slot_id, classified, previous_ids),
         :ok <- AuthorizeMemberProgramming.call(context, classified.members -- previous_ids) do
      athletes = Identity.list_by_ids(athlete_ids)

      if valid_athletes?(context, athlete_ids, athletes) do
        with {:ok, assignment} <- update_assigned_workout(context, id, params) do
          broadcast_assignment_refresh(context, previous_assignment, assignment)
          {:ok, assignment}
        end
      else
        {:error, :invalid_athletes}
      end
    end
  end

  defp update(_context, _id, _params), do: {:error, :organization_context_required}

  # ADR-186 §8: a coach changes only programmes inside their branches, and
  # moves them only between those.
  defp authorize_branches(_context, nil), do: :ok

  defp authorize_branches(context, assignment),
    do: CoveringBranches.authorize(context, CoveringBranches.of_row(assignment))

  defp branch_params(context, params) do
    case CoveringBranches.requested(params) do
      nil ->
        {:ok, params}

      requested ->
        with {:ok, target} <- CoveringBranches.for_new(context, requested),
             do: {:ok, CoveringBranches.put_columns(params, target)}
    end
  end

  defp reject_workout_reassignment(params) do
    if Map.has_key?(params, :master_workout_id) or Map.has_key?(params, "master_workout_id") do
      {:error, :workout_reassignment_not_supported}
    else
      :ok
    end
  end

  defp variant_member_booked(_context, nil, _classified, _previous_ids), do: :ok

  defp variant_member_booked(context, slot_id, %{members: [member_id]}, previous_ids) do
    if member_id in previous_ids do
      :ok
    else
      case Scheduling.get_slot(context, slot_id) do
        %{scheduled_at: %DateTime{} = scheduled_at} ->
          context
          |> Scheduling.list_member_slots(member_id, scheduled_at, DateTime.add(scheduled_at, 1))
          |> Enum.any?(&(&1.id == slot_id))
          |> if(do: :ok, else: {:error, :slot_not_booked_by_member})

        _missing ->
          {:error, :slot_not_booked_by_member}
      end
    end
  end

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
