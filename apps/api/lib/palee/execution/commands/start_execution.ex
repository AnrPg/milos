defmodule Palee.Execution.Commands.StartExecution do
  alias Palee.Execution.Commands.Params
  alias Palee.Execution.ExecutionStore
  alias Palee.Workouts

  def call(user_id, params) do
    workout_id = Params.get(params, :master_workout_id)
    scale_slug = Params.get(params, :scale_level_slug)

    # The workout is read in the execution's organization (ADR-133); the
    # caller derived it server-side before this command runs.
    workout_scope = %{organization_id: Params.get(params, :organization_id), user_id: user_id}

    with :ok <- validate_workout(workout_scope, workout_id, scale_slug),
         started_at_utc <- DateTime.utc_now(),
         execution_params <- %{
           # Always server-derived by AuthorizeWorkoutExecutionSource, which
           # Map.merge/2 puts ahead of anything the client sent (F-03).
           organization_id: Params.get(params, :organization_id),
           user_id: user_id,
           master_workout_id: workout_id,
           scale_level_slug: scale_slug,
           source: Params.get(params, :source),
           source_reference_id: Params.get(params, :source_reference_id),
           status: :active,
           started_at_utc: started_at_utc,
           started_at_tz: Params.get(params, :timezone) || "UTC",
           current_segment_index: 0,
           segment_started_at_utc: started_at_utc,
           paused_elapsed_ms: 0,
           resume_countdown_ends_at_utc: nil,
           # Server-derived by the caller (ADR-139), like the organization;
           # without one, the ADR-140 §9 default: in a gym, coach_can_view.
           journal_visibility:
             Params.get(params, :journal_visibility) ||
               default_rung(Params.get(params, :organization_id))
         } do
      ExecutionStore.start_execution(execution_params)
    end
  end

  defp default_rung(organization_id) when is_binary(organization_id), do: "coach_can_view"
  defp default_rung(_personal), do: "private"

  defp validate_workout(_scope, nil, _scale_slug), do: {:error, :bad_request}

  defp validate_workout(scope, workout_id, scale_slug) do
    case Workouts.get_workout(scope, workout_id) do
      missing when not is_map(missing) ->
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
