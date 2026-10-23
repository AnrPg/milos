defmodule Palee.Execution do
  alias Palee.Execution.Commands.{
    CompleteExecution,
    LogTrainingEntry,
    StartExecution,
    UpdateExecutionProgress,
    UpdateTrainingLogEntry,
    VoidTrainingLogEntry
  }

  alias Palee.Execution.Domain.{
    ExecutionAnalytics,
    ExecutionKpis,
    ModificationPatchValidator,
    TextSectionScores,
    TimerPresets,
    TimerSequenceBuilder,
    TrainingLogPolicy
  }

  alias Palee.Execution.Queries.{GetExecution, GetTrainingLogEntries}
  alias Palee.Execution.{ClassTimerStore, ExecutionStore, TrainingLogStore}

  defdelegate start_execution(user_id, params), to: StartExecution, as: :call
  defdelegate complete_execution(id, user_id, params), to: CompleteExecution, as: :call
  defdelegate complete_execution(id, user_id, params, opts), to: CompleteExecution, as: :call

  defdelegate update_execution_progress(id, user_id, params),
    to: UpdateExecutionProgress,
    as: :call

  @doc "A structured change as stored on a comment (ADR-140 §1)."
  defdelegate normalize_modification(patch), to: ModificationPatchValidator, as: :normalize
  defdelegate get_execution(id), to: GetExecution, as: :by_id
  defdelegate get_execution_for_user(id, user_id), to: GetExecution, as: :by_id_for_user
  defdelegate list_executions_for_user(user_id), to: GetExecution, as: :for_user

  def list_executions_for_coaching(user_id),
    do: ExecutionStore.list_executions_for_coaching(user_id)

  # Journal ladder (ADR-139): executions and training-log entries as feed
  # items, moved between rungs one by one or in bulk by a default change.
  defdelegate list_execution_items(user_id, bound, limit, scope), to: ExecutionStore
  defdelegate set_execution_visibility(id, user_id, rung), to: ExecutionStore
  defdelegate move_executions(user_id, from, to), to: ExecutionStore

  defdelegate list_training_log_items(user_id, bound, limit, scope),
    to: TrainingLogStore,
    as: :list_entry_items

  defdelegate set_training_log_visibility(id, user_id, rung),
    to: TrainingLogStore,
    as: :set_entry_visibility

  defdelegate move_training_log_entries(user_id, from, to),
    to: TrainingLogStore,
    as: :move_entries

  @doc "Execution KPI report for the current organization since `since`."
  def execution_kpis(%DateTime{} = since, user_ids \\ nil) do
    since
    |> ExecutionStore.list_executions_for_kpis(user_ids)
    |> ExecutionKpis.summarize()
    |> Map.put(:since, since)
  end

  def get_class_timer(context, scheduled_class_id),
    do: ClassTimerStore.get_class_timer(context, scheduled_class_id)

  def save_class_timer(context, scheduled_class_id, attrs, expected_version),
    do: ClassTimerStore.save_class_timer(context, scheduled_class_id, attrs, expected_version)

  @doc """
  The segments an execution of this workout runs. ADR-180: a workout written
  in text sections runs each section's own timer preset.
  """
  def build_timer_sequence(%{authoring_mode: "sectioned_text"} = workout),
    do: TimerPresets.build_sections(Map.get(workout, :sections) || [])

  def build_timer_sequence(workout), do: TimerSequenceBuilder.build(workout)

  @doc "ADR-180: the athlete's results for the scores a coach set on text sections."
  defdelegate normalize_text_section_scores(entries, sections),
    to: TextSectionScores,
    as: :normalize

  defdelegate text_section_metrics(workout), to: TextSectionScores, as: :section_metrics

  defdelegate preview_timer_sequence(workout), to: TimerSequenceBuilder, as: :preview

  # -- Analytics facts (ADR-123) ----------------------------------------------

  def with_execution_context(context, fun), do: ExecutionStore.with_user_context(context, fun)

  def list_stale_executions(started_before, started_after, limit),
    do: ExecutionStore.list_stale_executions(started_before, started_after, limit)

  def last_progress_at(execution_id), do: ExecutionStore.last_progress_at(execution_id)

  defdelegate completion_analytics_facts(execution, segments),
    to: ExecutionAnalytics,
    as: :completion_facts

  defdelegate abandonment_analytics_facts(execution, segments, now),
    to: ExecutionAnalytics,
    as: :abandonment_facts

  defdelegate execution_abandoned?(execution, now, threshold_hours),
    to: ExecutionAnalytics,
    as: :abandoned?

  # -- Standalone training log (ADR-118) -------------------------------------

  def with_training_log_context(context, fun),
    do: TrainingLogStore.with_tenant_context(context, fun)

  def with_training_log_owner_context(context, fun),
    do: TrainingLogStore.with_owner_context(context, fun)

  defdelegate log_training_entry(user_id, source, params, opts),
    to: LogTrainingEntry,
    as: :call

  defdelegate update_training_log_entry(entry_id, user_id, params, opts),
    to: UpdateTrainingLogEntry,
    as: :call

  defdelegate void_training_log_entry(entry_id, user_id, params, now),
    to: VoidTrainingLogEntry,
    as: :call

  defdelegate get_training_log_entry_for_user(id, user_id),
    to: GetTrainingLogEntries,
    as: :by_id_for_user

  defdelegate find_training_log_replay(user_id, params),
    to: GetTrainingLogEntries,
    as: :replay_for_request

  defdelegate list_training_log_entries_for_user(user_id, opts),
    to: GetTrainingLogEntries,
    as: :for_user

  defdelegate list_logged_training_source_ids(user_id, source_type),
    to: GetTrainingLogEntries,
    as: :live_source_reference_ids

  @doc """
  ADR-138 D6: every finished result of a workout in one gym between `from`
  and `to` (in-app executions and training-log entries alike), read in the
  gym's scope.
  """
  def list_workout_results(%{organization_id: organization_id} = context, workout_id, from, to) do
    Palee.Execution.ExecutionStore.with_user_context(context, fn ->
      executions =
        organization_id
        |> Palee.Execution.ExecutionStore.list_completed_for_workout(workout_id, from, to)
        |> Enum.map(&workout_result(&1, "execution", &1.completed_at_utc))

      entries =
        organization_id
        |> Palee.Execution.TrainingLogStore.list_for_workout(workout_id, from, to)
        |> Enum.map(&workout_result(&1, "training_log", &1.performed_at_utc))

      executions ++ entries
    end)
  end

  defp workout_result(row, source, at) do
    %{
      id: row.id,
      source: source,
      user_id: row.user_id,
      scale_level_slug: row.scale_level_slug,
      section_scores: row.section_scores || [],
      completed_at_utc: at,
      journal_visibility: row.journal_visibility
    }
  end

  defdelegate rank_workout_results(results, section),
    to: Palee.Execution.Domain.ScoreRanking,
    as: :rank

  defdelegate list_training_log_completions_for_user(user_id),
    to: GetTrainingLogEntries,
    as: :completion_records_for_user

  defdelegate training_log_completion_record(entry), to: TrainingLogPolicy, as: :completion_record

  defdelegate training_log_double_counted?(source, executions, performed_at),
    to: TrainingLogPolicy,
    as: :double_counted?

  defdelegate authorize_training_log_class(access, now),
    to: TrainingLogPolicy,
    as: :authorize_class

  defdelegate loggable_training_sources(candidates, logged_reference_ids, executions),
    to: TrainingLogPolicy,
    as: :loggable_candidates

  defdelegate training_log_scoreable_sections(workout),
    to: TrainingLogPolicy,
    as: :scoreable_sections

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: Palee.Execution.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)

  # ADR-162: one Vault across providers.
  alias Palee.Execution.Domain.{VaultFilter, WorkoutIdentity}

  defdelegate parse_vault_filter(params), to: VaultFilter, as: :parse
  defdelegate vault_filter_params(filter), to: VaultFilter, as: :to_params
  defdelegate vault_filter_active_count(filter), to: VaultFilter, as: :active_count
  defdelegate vault_attempt_matches?(filter, attempt), to: VaultFilter, as: :match?
  defdelegate exercise_matches?(exercise, names), to: VaultFilter, as: :exercise?
  defdelegate workout_identity(attrs), to: WorkoutIdentity, as: :key
  defdelegate identity_benchmark(key), to: WorkoutIdentity, as: :key_benchmark
  defdelegate benchmark_name(slug), to: WorkoutIdentity
end
