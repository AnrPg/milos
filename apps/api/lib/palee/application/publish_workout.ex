defmodule Palee.Application.PublishWorkout do
  require Logger

  alias Palee.Application.{
    BroadcastUserSync,
    SuggestWorkoutIcon,
    TenantStaffRecipients,
    TrackAnalyticsEvent
  }

  alias Palee.{Notifications, Scheduling, Workouts}

  def call(%{organization_id: _} = context, id, params) do
    substitute_for = parse_substitute_for(params)
    substitute_context = load_substitute_context(context, substitute_for)

    assignment_targets = Workouts.list_workout_change_targets(context, id)
    booking_targets = Scheduling.list_workout_change_targets(context, id)
    slot_ids = Scheduling.list_slot_ids_for_workout(context, id)
    is_republish = assignment_targets != [] or booking_targets != []

    with {:ok, workout} <- Workouts.publish_workout(context, id, params),
         :ok <- apply_substitution(context, substitute_for, workout.id) do
      Workouts.delete_superseded_drafts(context, id, workout.created_by_id)
      SuggestWorkoutIcon.enqueue(context, workout.id)
      maybe_notify(is_republish, substitute_for, assignment_targets, booking_targets, workout)
      broadcast_admin_workout_refresh(context, workout.id)

      track_publish(
        context,
        workout,
        is_republish,
        substitute_for,
        assignment_targets,
        booking_targets
      )

      maybe_broadcast_view_refresh(
        is_republish,
        substitute_for,
        substitute_context,
        assignment_targets,
        slot_ids,
        workout
      )

      {:ok, workout}
    end
  end

  def call(_context, _id, _params), do: {:error, :organization_context_required}

  defp parse_substitute_for(params) do
    case Map.get(params, "substitute_for") do
      %{"type" => "assignment", "id" => id} when is_binary(id) -> {:assignment, id}
      %{"type" => "slot", "id" => id} when is_binary(id) -> {:slot, id}
      _ -> nil
    end
  end

  defp apply_substitution(context, {:assignment, assignment_id}, new_workout_id) do
    case Workouts.substitute_assignment_workout(context, assignment_id, new_workout_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:substitution_failed, reason}}
    end
  end

  defp apply_substitution(context, {:slot, slot_id}, new_workout_id) do
    case Scheduling.substitute_slot_workout(context, slot_id, new_workout_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:substitution_failed, reason}}
    end
  end

  defp apply_substitution(_context, nil, _new_workout_id), do: :ok

  defp load_substitute_context(context, {:assignment, assignment_id}) do
    %{assignment: Workouts.get_assigned_workout(context, assignment_id)}
  end

  defp load_substitute_context(_context, {:slot, slot_id}) do
    %{slot_id: slot_id}
  end

  defp load_substitute_context(_context, nil), do: %{}

  # On global re-publish (no substitute context) notify all affected users.
  defp maybe_notify(true, nil, assignment_targets, booking_targets, workout) do
    notify_assignment_targets(assignment_targets, workout)
    notify_booking_targets(booking_targets, workout)
  end

  defp maybe_notify(
         _is_republish,
         _substitute_for,
         _assignment_targets,
         _booking_targets,
         _workout
       ),
       do: :ok

  defp maybe_broadcast_view_refresh(
         true,
         nil,
         _substitute_context,
         assignment_targets,
         slot_ids,
         workout
       ) do
    broadcast_assignment_sync(assignment_targets, "workout_republished", workout)
    broadcast_schedule_refresh(slot_ids, workout)
  end

  defp maybe_broadcast_view_refresh(
         _is_republish,
         {:assignment, _assignment_id},
         %{assignment: %{athlete_ids: athlete_ids, id: assignment_id}},
         _assignment_targets,
         _slot_ids,
         workout
       ) do
    broadcast_assignment_sync(
      Enum.map(athlete_ids, &%{user_id: &1}),
      "assignment_workout_substituted",
      workout,
      assignment_id
    )
  end

  defp maybe_broadcast_view_refresh(
         _is_republish,
         {:slot, _slot_id},
         %{slot_id: slot_id},
         _assignment_targets,
         _slot_ids,
         workout
       ) do
    broadcast_schedule_refresh([slot_id], workout)
  end

  defp maybe_broadcast_view_refresh(
         _is_republish,
         _substitute_for,
         _substitute_context,
         _assignment_targets,
         _slot_ids,
         _workout
       ),
       do: :ok

  defp broadcast_assignment_sync(targets, reason, workout, assignment_id \\ nil) do
    admin_ids = TenantStaffRecipients.user_ids(workout)

    payload =
      %{workout_id: workout.id}
      |> maybe_put(:assigned_workout_id, assignment_id)

    targets
    |> Enum.map(&Map.get(&1, :user_id))
    |> Kernel.++(admin_ids)
    |> BroadcastUserSync.for_users(
      ["assigned_workouts"],
      reason: reason,
      payload: payload
    )
  end

  defp broadcast_schedule_refresh([], _workout), do: :ok

  defp broadcast_schedule_refresh(slot_ids, workout) do
    Phoenix.PubSub.broadcast(
      Palee.PubSub,
      "schedule:workout_updated",
      {:schedule_workout_updated,
       %{
         workout_id: workout.id,
         organization_id: workout.organization_id,
         slot_ids: slot_ids
       }}
    )
  end

  defp notify_assignment_targets(targets, workout) do
    Enum.each(targets, fn target ->
      payload = %{
        kind: "assigned_workout",
        assigned_workout_id: target.assigned_workout_id,
        scheduled_for: Date.to_iso8601(target.scheduled_for),
        change_type: "sections_updated",
        workout_title: workout.title,
        url: "/my-workouts?open_assignment=#{target.assigned_workout_id}"
      }

      unless Notifications.enqueue_workout_changed(target.user_id, payload) == :ok do
        Logger.error("workout_changed assignment notification failed user_id=#{target.user_id}")
      end
    end)
  end

  defp notify_booking_targets(targets, workout) do
    Enum.each(targets, fn target ->
      training_type = Map.get(target, :training_type)

      payload = %{
        kind: "scheduled_class",
        scheduled_class_id: Map.get(target, :scheduled_class_id),
        training_type: to_string(training_type || ""),
        change_type: "sections_updated",
        workout_title: workout.title,
        url: "/schedule?open_slot=#{Map.get(target, :scheduled_class_id)}"
      }

      unless Notifications.enqueue_workout_changed(target.user_id, payload) == :ok do
        Logger.error("workout_changed booking notification failed user_id=#{target.user_id}")
      end
    end)
  end

  defp track_publish(context, workout, is_republish, substitute_for, assignments, bookings) do
    event =
      if is_republish or substitute_for, do: "workout_republished", else: "workout_published"

    TrackAnalyticsEvent.call(event, context, workout, %{
      metadata: %{
        affected_assignment_count: length(assignments),
        affected_booking_count: length(bookings),
        substitution: substitute_for && elem(substitute_for, 0)
      }
    })
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp broadcast_admin_workout_refresh(context, workout_id) do
    admin_ids = TenantStaffRecipients.user_ids(context)

    BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
      reason: "workout_published",
      payload: %{workout_id: workout_id}
    )
  end
end
