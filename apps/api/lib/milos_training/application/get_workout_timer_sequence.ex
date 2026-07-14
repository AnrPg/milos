defmodule MilosTraining.Application.GetWorkoutTimerSequence do
  alias MilosTraining.Application.AuthorizeWorkoutExecutionSource
  alias MilosTraining.{Execution, Workouts}

  def call(actor, workout_id, params \\ %{}) do
    scale_slug = params[:scale] || params["scale"]
    source = params[:source] || params["source"]
    source_reference_id = params[:source_reference_id] || params["source_reference_id"]

    with {:ok, _authorized_source} <-
           AuthorizeWorkoutExecutionSource.call(
             actor,
             workout_id,
             source,
             source_reference_id
           ),
         workout when not is_nil(workout) <- Workouts.get_workout(workout_id),
         {:ok, materialized_workout} <- materialize_workout(workout, scale_slug) do
      {:ok, Execution.build_timer_sequence(materialized_workout)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp materialize_workout(workout, nil), do: {:ok, workout}
  defp materialize_workout(workout, ""), do: {:ok, workout}

  defp materialize_workout(workout, scale_slug) do
    available_slugs =
      workout
      |> Map.get(:available_scale_levels, [])
      |> Enum.map(& &1.slug)

    if scale_slug in available_slugs do
      case Workouts.materialize_workout_for_scale(workout.id, scale_slug) do
        nil -> {:error, :invalid_scale_level}
        materialized -> {:ok, materialized}
      end
    else
      {:error, :invalid_scale_level}
    end
  end
end
