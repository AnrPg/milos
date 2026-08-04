defmodule MilosTraining.Application.UpdateScheduledSlot do
  alias MilosTraining.Application.ScheduleRealtime
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(context, id, params) do
    master_workout_id = params[:master_workout_id] || params["master_workout_id"]
    class_type_id = params[:class_type_id] || params["class_type_id"]

    with {:ok, _workout} <- fetch_workout(master_workout_id),
         {:ok, _class_type} <- fetch_class_type(context, class_type_id),
         {:ok, slot} <- update_slot(context, id, params) do
      broadcast_slot_updated(slot)
      {:ok, slot}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def call(id, params), do: call(nil, id, params)

  defp update_slot(nil, id, params), do: Scheduling.update_slot(id, params)
  defp update_slot(context, id, params), do: Scheduling.update_slot(context, id, params)

  defp fetch_workout(id) do
    case Workouts.get_workout(id) do
      nil -> {:error, :workout_not_found}
      workout -> {:ok, workout}
    end
  end

  defp fetch_class_type(nil, id) do
    case Scheduling.get_class_type(id) do
      nil -> {:error, :class_type_not_found}
      class_type -> {:ok, class_type}
    end
  end

  defp fetch_class_type(context, id) do
    case Scheduling.get_class_type(context, id) do
      nil -> {:error, :class_type_not_found}
      class_type -> {:ok, class_type}
    end
  end

  defp broadcast_slot_updated(slot) do
    ScheduleRealtime.broadcast("slot_updated", slot)
  end
end
