defmodule Palee.Application.AssignWorkout do
  @moduledoc """
  Assigns a published workout to athletes and - ADR-125 - members.

  Assignees are classified by their active membership role in the acting
  organization. Every assignee needs online programming or personal training
  in their package (ADR-225), checked before any write. A `source_slot_id`
  makes the assignment a class variant: one member's version of a class they
  booked. Assignees programmed through online programming then go through the
  ADR-040 coaching-touchpoint saga; personal training includes its programme.
  """

  alias Palee.Application.{
    AuthorizeProgramming,
    BroadcastUserSync,
    CoveringBranches,
    TenantAssigneeRoles,
    TenantStaffRecipients,
    TrackAnalyticsEvent
  }

  alias Palee.{Finance, Identity, Notifications, Scheduling, Workouts}
  alias Palee.Finance.Domain.ProgrammingGrant
  alias Palee.Workouts.Domain.AssignmentAudiencePolicy

  def call(%{organization_id: organization_id} = context, params)
      when is_binary(organization_id) do
    assignee_ids = athlete_ids(params)
    source_slot_id = source_slot_id(params)

    # ADR-186 §8: the programme is valid at the chosen branches, inside the
    # acting coach's own.
    with {:ok, target} <- CoveringBranches.for_new(context, CoveringBranches.requested(params)),
         params = CoveringBranches.put_columns(params, target),
         {:ok, roles} <- TenantAssigneeRoles.call(context, assignee_ids),
         {:ok, classified} <- AssignmentAudiencePolicy.classify(assignee_ids, roles),
         :ok <- AssignmentAudiencePolicy.validate_class_variant(source_slot_id, classified),
         {:ok, params} <- attach_source_slot(context, params, source_slot_id, classified),
         {:ok, grants} <- AuthorizeProgramming.grants(context, assignee_ids) do
      do_assign(context, params, Identity.list_by_ids(assignee_ids), classified, grants)
    end
  end

  def call(_context, _params), do: {:error, :organization_context_required}

  def call(_params), do: {:error, :organization_context_required}

  defp do_assign(context, params, athletes, classified, grants) do
    athlete_ids =
      params
      |> athlete_ids()

    if valid_athletes?(context, athlete_ids, athletes) do
      delivery_id = Ecto.UUID.generate()

      metered = Enum.filter(athletes, &ProgrammingGrant.meters_touchpoints?(grants[&1.id]))

      with {:ok, reservations} <- reserve_touchpoints(context, metered, delivery_id),
           {:ok, assignment} <- create_assignment(context, params, reservations),
           :ok <- finalize_touchpoints(context, reservations, assignment, delivery_id) do
        broadcast_assignment_refresh(context, assignment)
        dispatch_assignment_notification(context, assignment)

        TrackAnalyticsEvent.call("workout_assignment_created", context, assignment, %{
          metadata: %{
            athlete_count: length(classified.athletes),
            member_count: length(classified.members),
            kind: Map.get(assignment, :assignment_kind, "personal")
          }
        })

        {:ok, assignment}
      end
    else
      {:error, :invalid_athletes}
    end
  end

  defp source_slot_id(params) do
    case Map.get(params, :source_slot_id, Map.get(params, "source_slot_id")) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  # A class variant is linked to a class the single targeted member actually
  # holds an active (pending or approved) booking for. Its date defaults to
  # the class's day.
  defp attach_source_slot(_context, params, nil, _classified),
    do: {:ok, drop_keys(params, [:source_slot_id, "source_slot_id"])}

  defp attach_source_slot(context, params, slot_id, %{members: [member_id]}) do
    with {:ok, slot_id} <- cast_uuid(slot_id),
         %{scheduled_at: %DateTime{} = scheduled_at} <-
           Scheduling.get_slot(context, slot_id) || {:error, :slot_not_found},
         :ok <- booked_by_member(context, member_id, slot_id, scheduled_at) do
      scheduled_for =
        Map.get(params, :scheduled_for) || Map.get(params, "scheduled_for") ||
          DateTime.to_date(scheduled_at)

      {:ok,
       params
       |> drop_keys([:source_slot_id, "source_slot_id", "scheduled_for"])
       |> Map.put(:scheduled_for, scheduled_for)
       |> Map.put(:source_scheduled_class_id, slot_id)}
    end
  end

  defp booked_by_member(context, member_id, slot_id, scheduled_at) do
    context
    |> Scheduling.list_member_slots(member_id, scheduled_at, DateTime.add(scheduled_at, 1))
    |> Enum.any?(&(&1.id == slot_id))
    |> if(do: :ok, else: {:error, :slot_not_booked_by_member})
  end

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :slot_not_found}
    end
  end

  defp drop_keys(params, keys), do: Map.drop(params, keys)

  defp athlete_ids(params) do
    params
    |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
    |> List.wrap()
    |> Enum.uniq()
  end

  defp reserve_touchpoints(context, athletes, delivery_id) do
    Enum.reduce_while(athletes, {:ok, []}, fn athlete, {:ok, reservations} ->
      request = %{
        channel: :personal_programming,
        capability: :receive_coaching_touchpoints,
        allowance: :coaching_touchpoints,
        quantity: 1,
        occurred_on: Palee.Organizations.local_today(context.organization_id),
        source_context: "workouts",
        source_id: delivery_id,
        idempotency_key: "programming-delivery:#{delivery_id}:#{athlete.id}",
        metadata: %{"kind" => "programming_delivery"}
      }

      case reserve_entitlement(context, athlete.id, request) do
        {:ok, reservation} ->
          {:cont, {:ok, [{athlete.id, reservation} | reservations]}}

        error ->
          release_touchpoints(context, reservations, "Assignment entitlement reservation failed")
          {:halt, error}
      end
    end)
  end

  defp create_assignment(context, params, reservations) do
    case assign_workout(context, params) do
      {:ok, assignment} ->
        {:ok, assignment}

      {:error, reason} ->
        release_touchpoints(context, reservations, "Workout assignment creation failed")
        {:error, reason}
    end
  end

  defp finalize_touchpoints(context, reservations, assignment, delivery_id) do
    Enum.reduce_while(reservations, :ok, fn
      {_athlete_id, %{id: nil}}, :ok ->
        {:cont, :ok}

      {athlete_id, %{id: reservation_id}}, :ok ->
        case finalize_entitlement(context, reservation_id, %{
               source_id: assignment.id,
               reason: "Programming delivered",
               idempotency_key: "programming-delivery-finalized:#{delivery_id}:#{athlete_id}",
               metadata: %{"assignment_id" => assignment.id}
             }) do
          {:ok, _entry} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp release_touchpoints(context, reservations, reason) do
    Enum.each(reservations, fn
      {_athlete_id, %{id: nil}} ->
        :ok

      {_athlete_id, %{id: reservation_id}} ->
        release_entitlement(context, reservation_id, %{
          reason: reason,
          idempotency_key: "programming-delivery-release:#{reservation_id}"
        })
    end)

    :ok
  end

  defp valid_athletes?(_context, athlete_ids, athletes) do
    MapSet.new(athlete_ids) == MapSet.new(Enum.map(athletes, & &1.id))
  end

  defp broadcast_assignment_refresh(context, assignment) do
    admin_ids = TenantStaffRecipients.user_ids([context, assignment])

    BroadcastUserSync.for_users(
      (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids,
      ["assigned_workouts"],
      reason: "assignment_created",
      payload: %{assignment_id: assignment.id}
    )
  end

  defp dispatch_assignment_notification(context, assignment) do
    workout = Map.get(assignment, :workout) || %{}

    Notifications.dispatch_event(:workout_assigned, %{
      organization_id: context.organization_id,
      assignment_id: assignment.id,
      athlete_ids: Map.get(assignment, :athlete_ids, []) || [],
      workout_title: Map.get(workout, :title) || Map.get(workout, "title"),
      scheduled_for: assignment.scheduled_for,
      notification_batch_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    :ok
  end

  defp reserve_entitlement(context, user_id, request),
    do: Finance.reserve_entitlement(context, user_id, request)

  defp finalize_entitlement(context, reservation_id, params),
    do: Finance.finalize_entitlement(context, reservation_id, params)

  defp release_entitlement(context, reservation_id, params),
    do: Finance.release_entitlement(context, reservation_id, params)

  defp assign_workout(context, params), do: Workouts.assign_workout(context, params)
end
