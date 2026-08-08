defmodule MilosTraining.Application.CreateScheduledSlot do
  alias MilosTraining.Application.ScheduleRealtime
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(context, params) do
    master_workout_id =
      Map.get(params, :master_workout_id) || Map.get(params, "master_workout_id")

    class_type_id = Map.get(params, :class_type_id) || Map.get(params, "class_type_id")

    with {:ok, _workout} <- fetch_workout(context, master_workout_id),
         {:ok, _class_type} <- fetch_class_type(context, class_type_id),
         {:ok, slot} <- create_slot(context, params) do
      broadcast_slot_created(slot)
      {:ok, slot}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def call(_params), do: {:error, :organization_context_required}

  defp create_slot(context, params), do: Scheduling.create_slot(context, params)

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

  defp broadcast_slot_created(slot) do
    ScheduleRealtime.broadcast("slot_created", slot)
  end
end
