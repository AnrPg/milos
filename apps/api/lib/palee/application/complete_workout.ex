defmodule Palee.Application.CompleteWorkout do
  alias Palee.Application.{
    BroadcastUserSync,
    InjuryWarningEvaluation,
    InvalidateLandingPages,
    TenantStaffRecipients,
    TrackAnalyticsEvent
  }

  alias Palee.{Execution, Gamification, Identity, Journal, Notifications, Workouts}
  alias Palee.Execution.ExecutionStore
  alias Palee.Workouts.Queries.PlanPrescriptions
  alias Palee.Workers.ProcessWorkoutCompletionJob
  alias Palee.Workers.RefreshLeaderboardJob

  def call(context, execution_id, user_id, params),
    do:
      ExecutionStore.with_authorization_context(context, fn ->
        call(execution_id, user_id, params)
      end)

  def call(execution_id, user_id, params) do
    with {:ok, current_execution} <- fetch_execution(execution_id, user_id),
         {:ok, segments, workout} <- timer_sequence_for_execution(current_execution),
         {:ok, text_scores} <- text_section_scores(workout, params),
         {:ok, plan_sets} <- plan_actuals(workout, params),
         {:ok, execution} <-
           Execution.complete_execution(
             execution_id,
             user_id,
             Map.put(params, :segments, segments),
             [
               {:text_section_scores, text_scores},
               {:plan_sets, plan_sets} | completion_options(execution_id)
             ]
           ),
         :ok <- process_inline_if_needed(execution) do
      broadcast_completion(execution)

      TrackAnalyticsEvent.call("workout_execution_completed", nil, execution, %{
        user_id: user_id,
        metadata:
          execution
          |> Execution.completion_analytics_facts(segments)
          |> Map.merge(InjuryWarningEvaluation.completion_facts(execution, workout))
          |> Map.merge(plan_completion_facts(execution, workout))
      })

      {:ok, execution}
    end
  end

  # TD-092: the projection runs from `ProcessWorkoutCompletionJob`, outside any
  # request, so it opens its own session scope: the member (user_stats,
  # achievements and preferences are owner-only under RLS) inside the
  # completion's organization (settings, challenges and challenge progress are
  # tenant tables). Without it every read is empty and the first write is
  # rejected by the runtime role in production.
  def process_completion(%{user_id: _user_id} = execution) do
    execution
    |> projection_scope()
    |> Gamification.with_tenant_context(fn -> project_completion(execution) end)
  end

  defp projection_scope(%{user_id: user_id, organization_id: organization_id})
       when is_binary(organization_id),
       do: %{organization_id: organization_id, user_id: user_id}

  defp projection_scope(%{user_id: user_id}), do: %{user_id: user_id}

  defp project_completion(%{user_id: user_id} = execution) do
    account = Identity.find_by_id(user_id)
    settings = Gamification.get_settings()

    # ADR-118: live standalone training-log entries count as completions next
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
           workout_lookup: workout_lookup,
           recent_changes: recent_changes(user_id)
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
  (ADR-118). Voided entries are a no-op so a late job never crashes or
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
      Palee.PubSub,
      "workout:completed",
      {:workout_completed, execution}
    )
  end

  defp completion_options(execution_id) do
    if Application.get_env(:palee, :start_oban, true) do
      [completion_job: ProcessWorkoutCompletionJob.new(%{execution_id: execution_id})]
    else
      []
    end
  end

  defp process_inline_if_needed(execution) do
    if Application.get_env(:palee, :start_oban, true),
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

  defp timer_sequence_for_execution(%{master_workout_id: nil}), do: {:ok, [], nil}

  defp timer_sequence_for_execution(%{
         master_workout_id: workout_id,
         scale_level_slug: scale_slug,
         organization_id: organization_id,
         user_id: user_id
       }) do
    # See Palee.Application.UpdateExecutionProgress: the /api/executions
    # routes are user-scoped, not org-scoped, so the outer context here never
    # carries an organization_id. Re-open the tenant scope using the
    # execution's own organization so the workout lookup below can see it,
    # instead of silently completing against zero timer segments.
    context = %{organization_id: organization_id, user_id: user_id}

    case resolve_workout(context, workout_id, scale_slug) do
      %{} = workout -> {:ok, Execution.build_timer_sequence(workout), workout}
      _missing -> {:ok, [], nil}
    end
  end

  # ADR-180: the athlete's results for the scores the coach set on the
  # sections of a workout written without the assistant.
  defp text_section_scores(%{authoring_mode: "sectioned_text", sections: sections}, params),
    do:
      Execution.normalize_text_section_scores(
        params[:text_section_scores] || params["text_section_scores"],
        sections || []
      )

  defp text_section_scores(_workout, _params), do: {:ok, []}

  # ADR-270: the volume of a structured plan workout for analytics, next to
  # the set counts and tonnage of its actuals (`ExecutionAnalytics`): kg ×
  # reps with what the actuals lack read from the plan (% loads through the
  # 1RM, ranges at their midpoint, scored rounds of an AMRAP done without
  # actuals), and whether any of it is an estimate.
  defp plan_completion_facts(execution, %{} = workout) do
    if PlanPrescriptions.plan_workout?(workout) do
      case PlanPrescriptions.workload(workout, Map.get(execution, :plan_sets) || [],
             section_scores: execution.section_scores,
             section_elapsed_ms: Map.get(execution, :section_elapsed_ms)
           ) do
        %{totals: totals} ->
          %{
            authoring_mode: "structured_plan",
            plan_volume_kg: totals.volume_kg,
            plan_volume_estimated: totals.estimated
          }

        nil ->
          %{authoring_mode: "structured_plan"}
      end
    else
      %{}
    end
  end

  defp plan_completion_facts(_execution, _workout), do: %{}

  # ADR-270: what the athlete did in each set / round of a structured plan,
  # checked against the plan rows of the workout's sections. Other workouts
  # keep no plan actuals.
  defp plan_actuals(%{authoring_mode: "structured_plan", sections: sections}, params),
    do:
      Execution.normalize_plan_actuals(
        params[:plan_actuals] || params["plan_actuals"],
        Workouts.plan_rows_by_section(sections || [])
      )

  defp plan_actuals(_workout, _params), do: {:ok, []}

  defp resolve_workout(context, workout_id, slug) when slug in [nil, ""],
    do: Workouts.get_workout(context, workout_id)

  defp resolve_workout(context, workout_id, scale_slug),
    do: Workouts.materialize_workout_for_scale(context, workout_id, scale_slug)

  # Each completion's workout is read in the organization it was done in; the
  # projection job itself runs without a tenant session (ADR-133).
  defp build_workout_lookup(executions) do
    executions
    |> Enum.filter(
      &(is_binary(&1.master_workout_id) and is_binary(Map.get(&1, :organization_id)))
    )
    |> Enum.uniq_by(&{&1.organization_id, &1.master_workout_id})
    |> Enum.reduce(%{}, fn completion, acc ->
      context = %{organization_id: completion.organization_id, user_id: completion.user_id}

      case Workouts.get_workout(context, completion.master_workout_id) do
        %{} = workout -> Map.put(acc, completion.master_workout_id, workout)
        _missing -> acc
      end
    end)
  end

  # Perseverance looks back 7 training days; off days can stretch that, so
  # read a generous window and let the calculator pick the days.
  @changes_lookback_days 21

  defp recent_changes(user_id) do
    since = DateTime.add(DateTime.utc_now(), -@changes_lookback_days * 86_400, :second)

    user_id
    |> Journal.list_changes_since(since)
    |> Enum.map(&Map.put(&1.change, "logged_at", &1.written_at))
  end
end
