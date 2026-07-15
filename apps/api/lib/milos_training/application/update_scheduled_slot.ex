defmodule MilosTraining.Application.UpdateScheduledSlot do
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(id, params) do
    master_workout_id = params[:master_workout_id] || params["master_workout_id"]
    class_type_id = params[:class_type_id] || params["class_type_id"]

    with {:ok, _workout} <- fetch_workout(master_workout_id),
         {:ok, _class_type} <- fetch_class_type(class_type_id),
         {:ok, slot} <- Scheduling.update_slot(id, params) do
      broadcast_slot_updated(slot)
      {:ok, slot}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_workout(id) do
    case Workouts.get_workout(id) do
      nil -> {:error, :workout_not_found}
      workout -> {:ok, workout}
    end
  end

  defp fetch_class_type(id) do
    case Scheduling.get_class_type(id) do
      nil -> {:error, :class_type_not_found}
      class_type -> {:ok, class_type}
    end
  end

  defp broadcast_slot_updated(slot) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "schedule:slot_updated",
      {:schedule_slot_updated, slot}
    )
  end
end
