defmodule MilosTraining.Application.CompleteWorkout do
  alias MilosTraining.Application.{
    BroadcastUserSync,
    InvalidateLandingPages,
    TenantStaffRecipients,
    TrackAnalyticsEvent
  }

  alias MilosTraining.{Execution, Gamification, Identity, Notifications, Workouts}
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.Workers.ProcessWorkoutCompletionJob
  alias MilosTraining.Workers.RefreshLeaderboardJob

  def call(context, execution_id, user_id, params),
    do:
      ExecutionStore.with_authorization_context(context, fn ->
        call(execution_id, user_id, params)
      end)

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

      TrackAnalyticsEvent.call("workout_execution_completed", nil, execution, %{
        user_id: user_id,
        metadata: Execution.completion_analytics_facts(execution, segments)
      })

      {:ok, execution}
    end
  end

  def process_completion(%{user_id: user_id} = execution) do
    account = Identity.find_by_id(user_id)
    settings = Gamification.get_settings()

    # ADR-100: live standalone training-log entries count as completions next
    # to finished executions, so streaks, totals, badges and challenges see
    # class/offline workouts too. Voided entries are excluded here, which is
    # how a void stops counting on the next projection run.
    completed_executions =
      user_id
      |> Execution.list_executions_for_user()
      |> Enum.filter(& &1.completed_at_utc)
      |> Kernel.++(training_log_completions(user_id))
      |> Enum.sort_by(&DateTime.to_unix(&1.completed_at_utc, :microsecond))

    workout_lookup = build_workout_lookup(completed_executions)
    admin_ids = TenantStaffRecipients.user_ids(execution)

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

  @doc """
  Runs the completion projection for a standalone training-log entry
  (ADR-100). Voided entries are a no-op so a late job never crashes or
  counts them.
  """
  def process_training_log_completion(entry) do
    case Execution.training_log_completion_record(entry) do
      nil -> :ok
      completion -> process_completion(completion)
    end
  end

  defp training_log_completions(user_id) do
    case Execution.with_training_log_owner_context(%{user_id: user_id}, fn ->
           Execution.list_training_log_completions_for_user(user_id)
         end) do
      completions when is_list(completions) -> completions
      _error -> []
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
         scale_level_slug: scale_slug,
         organization_id: organization_id,
         user_id: user_id
       }) do
    # See MilosTraining.Application.UpdateExecutionProgress: the /api/executions
    # routes are user-scoped, not org-scoped, so the outer context here never
    # carries an organization_id. Re-open the tenant scope using the
    # execution's own organization so the workout lookup below can see it,
    # instead of silently completing against zero timer segments.
    Workouts.with_tenant_context(%{organization_id: organization_id, user_id: user_id}, fn ->
      case resolve_workout(workout_id, scale_slug) do
        nil -> {:ok, []}
        workout -> {:ok, Execution.build_timer_sequence(workout)}
      end
    end)
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
