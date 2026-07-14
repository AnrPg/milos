defmodule MilosTraining.Application.CreateScheduledSlot do
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(params) do
    master_workout_id =
      Map.get(params, :master_workout_id) || Map.get(params, "master_workout_id")

    with %{type: training_type} <- Workouts.get_workout(master_workout_id),
         slot_params <- put_training_type(params, training_type),
         {:ok, slot} <- Scheduling.create_slot(slot_params) do
      broadcast_slot_created(slot)
      {:ok, slot}
    else
      nil -> {:error, :workout_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_slot_created(slot) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "schedule:slot_created",
      {:schedule_slot_created, slot}
    )
  end

  defp put_training_type(params, training_type) do
    cond do
      has_atom_keys?(params) ->
        params
        |> Map.delete("training_type")
        |> Map.put(:training_type, training_type)

      true ->
        params
        |> Map.delete(:training_type)
        |> Map.put("training_type", to_string(training_type))
    end
  end

  defp has_atom_keys?(params) do
    Enum.any?(Map.keys(params), &is_atom/1)
  end
end
