defmodule MilosTraining.Application.CreateScheduledSlot do
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(params) do
    master_workout_id =
      Map.get(params, :master_workout_id) || Map.get(params, "master_workout_id")

    class_type_id = Map.get(params, :class_type_id) || Map.get(params, "class_type_id")

    with {:ok, _workout} <- fetch_workout(master_workout_id),
         {:ok, _class_type} <- fetch_class_type(class_type_id),
         {:ok, slot} <- Scheduling.create_slot(params) do
      broadcast_slot_created(slot)
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

  defp broadcast_slot_created(slot) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "schedule:slot_created",
      {:schedule_slot_created, slot}
    )
  end
end
