defmodule MilosTraining.Application.UpdateScheduledSlot do
  alias MilosTraining.Application.{ClassLocation, PromoteClassWaitlist, ScheduleRealtime}
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(context, id, params) do
    master_workout_id = params[:master_workout_id] || params["master_workout_id"]
    class_type_id = params[:class_type_id] || params["class_type_id"]

    with {:ok, _workout} <- fetch_workout(context, master_workout_id),
         {:ok, _class_type} <- fetch_class_type(context, class_type_id),
         :ok <- ClassLocation.check(context, params),
         {:ok, slot} <- update_slot(context, id, params) do
      broadcast_slot_updated(slot)
      # A larger capacity may admit waitlisted members (ADR-097).
      PromoteClassWaitlist.call(context, slot.id)
      {:ok, slot}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def call(_id, _params), do: {:error, :organization_context_required}

  defp update_slot(context, id, params), do: Scheduling.update_slot(context, id, params)

  defp fetch_workout(context, id) do
    case Workouts.get_workout(context, id) do
      nil -> {:error, :workout_not_found}
      workout -> {:ok, workout}
    end
  end

  defp fetch_class_type(context, id) do
    case Scheduling.get_class_type(context, id) do
      nil -> {:error, :class_type_not_found}
      {:error, reason} -> {:error, reason}
      class_type -> {:ok, class_type}
    end
  end

  defp broadcast_slot_updated(slot) do
    ScheduleRealtime.broadcast("slot_updated", slot)
  end
end
