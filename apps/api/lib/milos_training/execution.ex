defmodule MilosTraining.Execution do
  alias MilosTraining.Execution.Commands.{
    CompleteExecution,
    LogTrainingEntry,
    StartExecution,
    SubmitExecutionNote,
    UpdateExecutionProgress,
    UpdateTrainingLogEntry,
    VoidTrainingLogEntry
  }

  alias MilosTraining.Execution.Domain.{
    ExecutionAnalytics,
    ExecutionKpis,
    TimerSequenceBuilder,
    TrainingLogPolicy
  }

  alias MilosTraining.Execution.Queries.{GetExecution, GetTrainingLogEntries}
  alias MilosTraining.Execution.{ClassTimerStore, ExecutionStore, TrainingLogStore}

  defdelegate start_execution(user_id, params), to: StartExecution, as: :call
  defdelegate complete_execution(id, user_id, params), to: CompleteExecution, as: :call
  defdelegate complete_execution(id, user_id, params, opts), to: CompleteExecution, as: :call

  defdelegate update_execution_progress(id, user_id, params),
    to: UpdateExecutionProgress,
    as: :call

  defdelegate submit_execution_note(id, user_id, params), to: SubmitExecutionNote, as: :call
  defdelegate get_execution(id), to: GetExecution, as: :by_id
  defdelegate get_execution_for_user(id, user_id), to: GetExecution, as: :by_id_for_user
  defdelegate list_executions_for_user(user_id), to: GetExecution, as: :for_user

  def list_executions_for_coaching(user_id),
    do: ExecutionStore.list_executions_for_coaching(user_id)

  @doc "Execution KPI report for the current organization since `since`."
  def execution_kpis(%DateTime{} = since) do
    since
    |> ExecutionStore.list_executions_for_kpis()
    |> ExecutionKpis.summarize()
    |> Map.put(:since, since)
  end

  def get_class_timer(context, scheduled_class_id),
    do: ClassTimerStore.get_class_timer(context, scheduled_class_id)

  def save_class_timer(context, scheduled_class_id, attrs, expected_version),
    do: ClassTimerStore.save_class_timer(context, scheduled_class_id, attrs, expected_version)

  defdelegate build_timer_sequence(workout), to: TimerSequenceBuilder, as: :build
  defdelegate preview_timer_sequence(workout), to: TimerSequenceBuilder, as: :preview

  # -- Analytics facts (ADR-113) ----------------------------------------------

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

  # -- Standalone training log (ADR-108) -------------------------------------

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

  # ADR-107 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Execution.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
