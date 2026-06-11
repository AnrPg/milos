defmodule MilosTraining.Application.DeleteWorkout do
  require Logger

  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Execution, Identity, Scheduling, Workouts}
  alias MilosTraining.Notifications

  def call(id) do
    with %{id: ^id} <- Workouts.get_workout_for_admin(id),
         assignment_targets <- Workouts.list_workout_change_targets(id),
         booking_targets <- Scheduling.list_workout_change_targets(id),
         {:ok, deleted_slot_ids} <- Scheduling.delete_slots_for_workout(id),
         {:ok, _deleted_execution_ids} <- Execution.delete_executions_for_workout(id),
         :ok <- Workouts.delete_workout(id) do
      broadcast_deleted_slots(deleted_slot_ids)
      notify_assignment_targets(assignment_targets)
      notify_booking_targets(booking_targets)
      broadcast_assignment_refresh(assignment_targets, id)
      broadcast_admin_workout_refresh(id)
      :ok
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_deleted_slots(slot_ids) do
    Enum.each(slot_ids, fn slot_id ->
      Phoenix.PubSub.broadcast(
        MilosTraining.PubSub,
        "schedule:slot_deleted",
        {:schedule_slot_deleted, %{slot_id: slot_id}}
      )
    end)
  end

  defp notify_assignment_targets(targets) do
    Enum.each(targets, fn target ->
      payload = %{
        kind: "assigned_workout",
        assigned_workout_id: target.assigned_workout_id,
        scheduled_for: Date.to_iso8601(target.scheduled_for),
        body:
          "The coach removed your workout scheduled for #{format_date(target.scheduled_for)}. This workout no longer exists.",
        url: "/my-workouts?open_assignment=#{target.assigned_workout_id}"
      }

      unless Notifications.enqueue_workout_deleted(target.user_id, payload) == :ok do
        Logger.error(
          "workout_deleted assignment notification failed user_id=#{target.user_id} assigned_workout_id=#{target.assigned_workout_id}"
        )
      end
    end)
  end

  defp notify_booking_targets(targets) do
    Enum.each(targets, fn target ->
      payload = %{
        kind: "scheduled_class",
        scheduled_class_id: target.scheduled_class_id,
        scheduled_at: DateTime.to_iso8601(target.scheduled_at),
        training_type: to_string(target.training_type),
        body:
          "The coach removed the workout for your #{format_training_type(target.training_type)} class on #{format_datetime(target.scheduled_at)}. This class may be rescheduled.",
        url: "/schedule?open_slot=#{target.scheduled_class_id}"
      }

      unless Notifications.enqueue_workout_deleted(target.user_id, payload) == :ok do
        Logger.error(
          "workout_deleted booking notification failed user_id=#{target.user_id} scheduled_class_id=#{target.scheduled_class_id}"
        )
      end
    end)
  end

  defp format_date(date), do: Calendar.strftime(date, "%b %d, %Y")

  defp format_datetime(datetime),
    do: Calendar.strftime(datetime, "%b %d, %Y at %H:%M UTC")

  defp format_training_type(training_type) do
    training_type
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp broadcast_assignment_refresh(targets, workout_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    targets
    |> Enum.map(&Map.get(&1, :user_id))
    |> Kernel.++(admin_ids)
    |> BroadcastUserSync.for_users(
      ["assigned_workouts"],
      reason: "workout_deleted",
      payload: %{workout_id: workout_id}
    )
  end

  defp broadcast_admin_workout_refresh(workout_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
      reason: "workout_deleted",
      payload: %{workout_id: workout_id}
    )
  end
end
