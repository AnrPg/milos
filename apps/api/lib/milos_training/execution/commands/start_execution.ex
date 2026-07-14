defmodule MilosTraining.Execution.Commands.StartExecution do
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.Workouts

  def call(user_id, params) do
    workout_id = params[:master_workout_id] || params["master_workout_id"]
    scale_slug = params[:scale_level_slug] || params["scale_level_slug"]

    with :ok <- validate_workout(workout_id, scale_slug),
         started_at_utc <- DateTime.utc_now(),
         execution_params <- %{
           user_id: user_id,
           master_workout_id: workout_id,
           scale_level_slug: scale_slug,
           source: params[:source] || params["source"],
           source_reference_id: params[:source_reference_id] || params["source_reference_id"],
           status: :active,
           started_at_utc: started_at_utc,
           started_at_tz: params[:timezone] || params["timezone"] || "UTC",
           current_segment_index: 0,
           segment_started_at_utc: started_at_utc,
           paused_elapsed_ms: 0,
           resume_countdown_ends_at_utc: nil
         } do
      ExecutionStore.start_execution(execution_params)
    end
  end

  defp validate_workout(nil, _scale_slug), do: {:error, :bad_request}

  defp validate_workout(workout_id, scale_slug) do
    case Workouts.get_workout(workout_id) do
      nil ->
        {:error, :workout_not_found}

      workout when not is_nil(scale_slug) ->
        available_slugs =
          workout
          |> Map.get(:available_scale_levels, [])
          |> Enum.map(& &1.slug)

        if scale_slug in available_slugs,
          do: :ok,
          else: {:error, :invalid_scale_level}

      _workout ->
        :ok
    end
  end
end
