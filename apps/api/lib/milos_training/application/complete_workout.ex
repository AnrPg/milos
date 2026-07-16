defmodule MilosTraining.Application.CompleteWorkout do
  alias MilosTraining.Application.{BroadcastUserSync, InvalidateLandingPages}
  alias MilosTraining.{Execution, Gamification, Identity, Notifications, Workouts}
  alias MilosTraining.Workers.ProcessWorkoutCompletionJob
  alias MilosTraining.Workers.RefreshLeaderboardJob

  def call(execution_id, user_id, params) do
    with {:ok, current_execution} <- fetch_execution(execution_id, user_id),
         {:ok, segments} <- timer_sequence_for_execution(current_execution),
         {:ok, execution} <-
           Execution.complete_execution(
             execution_id,
             user_id,
             Map.put(params, :segments, segments),
             completion_options(execution_id)
           ),
         :ok <- process_inline_if_needed(execution) do
      broadcast_completion(execution)
      {:ok, execution}
    end
  end

  def process_completion(%{user_id: user_id} = execution) do
    account = Identity.find_by_id(user_id)
    settings = Gamification.get_settings()

    completed_executions =
      user_id
      |> Execution.list_executions_for_user()
      |> Enum.filter(& &1.completed_at_utc)
      |> Enum.sort_by(&DateTime.to_unix(&1.completed_at_utc, :microsecond))

    workout_lookup = build_workout_lookup(completed_executions)
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    case Gamification.record_workout_completion(%{
           execution: execution,
           account: account,
           settings: settings,
           completed_executions: completed_executions,
           workout_lookup: workout_lookup
         }) do
      {:ok, result} ->
        _ = refresh_leaderboard()
        InvalidateLandingPages.for_users([user_id | admin_ids])

        BroadcastUserSync.for_user(
          user_id,
          ["landing"],
          reason: "challenge_progress_advanced",
          payload: %{increments: result.challenge_increments}
        )

        BroadcastUserSync.for_users(
          admin_ids,
          ["admin_challenges"],
          reason: "challenge_progress_updated",
          payload: %{user_id: user_id, execution_id: execution.id}
        )

        _ = dispatch_challenge_notifications(result.challenge_completions)
        :ok

      error ->
        InvalidateLandingPages.for_users([user_id | admin_ids])
        error
    end
  end

  defp broadcast_completion(execution) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "workout:completed",
      {:workout_completed, execution}
    )
  end

  defp completion_options(execution_id) do
    if Application.get_env(:milos_training, :start_oban, true) do
      [completion_job: ProcessWorkoutCompletionJob.new(%{execution_id: execution_id})]
    else
      []
    end
  end

  defp process_inline_if_needed(execution) do
    if Application.get_env(:milos_training, :start_oban, true),
      do: :ok,
      else: process_completion(execution)
  end

  defp dispatch_challenge_notifications(challenge_completions) do
    Enum.reduce_while(challenge_completions, :ok, fn payload, :ok ->
      case Notifications.dispatch_event(:challenge_completed, Map.put_new(payload, :url, "/")) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp refresh_leaderboard do
    %{}
    |> RefreshLeaderboardJob.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, _reason} -> Gamification.refresh_leaderboard()
    end
  rescue
    _error -> Gamification.refresh_leaderboard()
  end

  defp fetch_execution(execution_id, user_id) do
    case Execution.get_execution(execution_id) do
      nil -> {:error, :not_found}
      %{user_id: ^user_id} = execution -> {:ok, execution}
      %{} -> {:error, :forbidden}
    end
  end

  defp timer_sequence_for_execution(%{master_workout_id: nil}), do: {:ok, []}

  defp timer_sequence_for_execution(%{
         master_workout_id: workout_id,
         scale_level_slug: scale_slug
       }) do
    case resolve_workout(workout_id, scale_slug) do
      nil -> {:ok, []}
      workout -> {:ok, Execution.build_timer_sequence(workout)}
    end
  end

  defp resolve_workout(workout_id, nil), do: Workouts.get_workout(workout_id)
  defp resolve_workout(workout_id, ""), do: Workouts.get_workout(workout_id)

  defp resolve_workout(workout_id, scale_slug),
    do: Workouts.materialize_workout_for_scale(workout_id, scale_slug)

  defp build_workout_lookup(executions) do
    executions
    |> Enum.map(& &1.master_workout_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn workout_id, acc ->
      case Workouts.get_workout(workout_id) do
        nil -> acc
        workout -> Map.put(acc, workout_id, workout)
      end
    end)
  end
end
