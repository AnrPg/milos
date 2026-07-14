defmodule MilosTraining.Application.UpdateScheduledSlot do
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(id, params) do
    master_workout_id = params[:master_workout_id] || params["master_workout_id"]

    with %{type: training_type} <- Workouts.get_workout(master_workout_id),
         slot_params <- put_training_type(params, training_type),
         {:ok, slot} <- Scheduling.update_slot(id, slot_params) do
      broadcast_slot_updated(slot)
      {:ok, slot}
    else
      nil -> {:error, :workout_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_slot_updated(slot) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "schedule:slot_updated",
      {:schedule_slot_updated, slot}
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
