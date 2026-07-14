defmodule MilosTraining.Application.UpdateExecutionProgress do
  alias MilosTraining.{Execution, Workouts}

  def call(execution_id, user_id, params) do
    with {:ok, current_execution} <- fetch_execution(execution_id, user_id),
         {:ok, segments} <- timer_sequence_for_execution(current_execution),
         {:ok, execution} <-
           Execution.update_execution_progress(
             execution_id,
             user_id,
             Map.put(params, :segments, segments)
           ) do
      broadcast_progress_updated(execution)
      {:ok, execution}
    end
  end

  defp fetch_execution(execution_id, user_id) do
    case Execution.get_execution(execution_id) do
      nil -> {:error, :not_found}
      %{user_id: ^user_id} = execution -> {:ok, execution}
      %{} -> {:error, :forbidden}
    end
  end

  defp timer_sequence_for_execution(%{master_workout_id: nil}), do: {:ok, []}

  defp timer_sequence_for_execution(%{master_workout_id: workout_id, scale_level_slug: scale_slug}) do
    case resolve_workout(workout_id, scale_slug) do
      nil -> {:ok, []}
      workout -> {:ok, Execution.build_timer_sequence(workout)}
    end
  end

  defp resolve_workout(workout_id, nil), do: Workouts.get_workout(workout_id)
  defp resolve_workout(workout_id, ""), do: Workouts.get_workout(workout_id)

  defp resolve_workout(workout_id, scale_slug),
    do: Workouts.materialize_workout_for_scale(workout_id, scale_slug)

  defp broadcast_progress_updated(execution) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "execution:progress_updated",
      {:execution_progress_updated, execution}
    )
  end
end
