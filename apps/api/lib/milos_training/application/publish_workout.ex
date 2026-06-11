defmodule MilosTraining.Application.PublishWorkout do
  require Logger

  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Notifications, Scheduling, Workouts}

  def call(id, params) do
    substitute_for = parse_substitute_for(params)
    substitute_context = load_substitute_context(substitute_for)

    # Gather affected users before publish so we capture pre-publish assignment/booking state.
    # For substitutes the duplicate has no existing assignments so these will be empty.
    assignment_targets = Workouts.list_workout_change_targets(id)
    booking_targets = Scheduling.list_workout_change_targets(id)
    slot_ids = Scheduling.list_slot_ids_for_workout(id)
    is_republish = assignment_targets != [] or booking_targets != []

    with {:ok, workout} <- Workouts.publish_workout(id, params),
         :ok <- apply_substitution(substitute_for, workout.id) do
      maybe_notify(is_republish, substitute_for, assignment_targets, booking_targets, workout)
      broadcast_admin_workout_refresh(workout.id)

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

  defp parse_substitute_for(params) do
    case Map.get(params, "substitute_for") do
      %{"type" => "assignment", "id" => id} when is_binary(id) -> {:assignment, id}
      %{"type" => "slot", "id" => id} when is_binary(id) -> {:slot, id}
      _ -> nil
    end
  end

  defp apply_substitution({:assignment, assignment_id}, new_workout_id) do
    case Workouts.substitute_assignment_workout(assignment_id, new_workout_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:substitution_failed, reason}}
    end
  end

  defp apply_substitution({:slot, slot_id}, new_workout_id) do
    case Scheduling.substitute_slot_workout(slot_id, new_workout_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:substitution_failed, reason}}
    end
  end

  defp apply_substitution(nil, _new_workout_id), do: :ok

  defp load_substitute_context({:assignment, assignment_id}) do
    %{assignment: Workouts.get_assigned_workout(assignment_id)}
  end

  defp load_substitute_context({:slot, slot_id}) do
    %{slot_id: slot_id}
  end

  defp load_substitute_context(nil), do: %{}

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
    broadcast_assignment_sync(assignment_targets, "workout_republished", workout.id)
    broadcast_schedule_refresh(slot_ids, workout.id)
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
      workout.id,
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
    broadcast_schedule_refresh([slot_id], workout.id)
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

  defp broadcast_assignment_sync(targets, reason, workout_id, assignment_id \\ nil) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    payload =
      %{workout_id: workout_id}
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

  defp broadcast_schedule_refresh([], _workout_id), do: :ok

  defp broadcast_schedule_refresh(slot_ids, workout_id) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "schedule:workout_updated",
      {:schedule_workout_updated, %{workout_id: workout_id, slot_ids: slot_ids}}
    )
  end

  defp notify_assignment_targets(targets, workout) do
    Enum.each(targets, fn target ->
      payload = %{
        kind: "assigned_workout",
        assigned_workout_id: target.assigned_workout_id,
        scheduled_for: Date.to_iso8601(target.scheduled_for),
        change_type: "sections_updated",
        body:
          "Your coach updated the exercises for your workout on #{format_date(target.scheduled_for)}: #{workout.title}.",
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
        body:
          "Your coach updated the exercises for your #{format_training_type(training_type)} class: #{workout.title}.",
        url: "/schedule?open_slot=#{Map.get(target, :scheduled_class_id)}"
      }

      unless Notifications.enqueue_workout_changed(target.user_id, payload) == :ok do
        Logger.error("workout_changed booking notification failed user_id=#{target.user_id}")
      end
    end)
  end

  defp format_date(date), do: Calendar.strftime(date, "%b %d, %Y")

  defp format_training_type(nil), do: "training"

  defp format_training_type(training_type) do
    training_type
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp broadcast_admin_workout_refresh(workout_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
      reason: "workout_published",
      payload: %{workout_id: workout_id}
    )
  end
end
