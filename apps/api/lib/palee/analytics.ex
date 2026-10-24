defmodule Palee.Analytics do
  alias Palee.Analytics.Commands.{
    RecordAttendance,
    RecordCommunicationMessage,
    RecordEvent,
    RecordNotificationClick,
    RecordPushAttempt,
    UpsertExerciseCatalogEntry
  }

  alias Palee.Analytics.AnalyticsStore
  alias Palee.Analytics.Domain.{EventCatalog, ExecutionInteraction}
  alias Palee.Analytics.Queries.{AnalyticsSummary, GetAttendance}

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: AnalyticsStore.with_tenant_context(context, fun)

  defdelegate record_event(params), to: RecordEvent, as: :call
  defdelegate record_events(params_list), to: RecordEvent, as: :call_many

  # ADR-123 event registry and client interaction allowlist.
  defdelegate build_event(event_name, actor, subject, extra), to: EventCatalog, as: :build
  defdelegate event_names(), to: EventCatalog
  defdelegate execution_interaction_kinds(), to: ExecutionInteraction, as: :kinds
  defdelegate execution_interaction_fields(), to: ExecutionInteraction, as: :fields
  defdelegate execution_interaction_max_batch(), to: ExecutionInteraction, as: :max_batch

  defdelegate validate_execution_interactions(events, now),
    to: ExecutionInteraction,
    as: :validate_batch

  def list_recorded_dedupe_keys(event_name, keys),
    do: AnalyticsStore.list_recorded_dedupe_keys(event_name, keys)

  @doc """
  `{event_name, source_context_id}` pairs recorded in the current tenant for
  `event_names` whose metadata `source_context_id` is one of
  `source_context_ids` (TD-088: ready-screen injury warnings per execution).
  """
  def list_events_for_source_contexts(event_names, source_context_ids),
    do: AnalyticsStore.list_events_for_source_contexts(event_names, source_context_ids)

  defdelegate record_notification_click(params), to: RecordNotificationClick, as: :call
  defdelegate record_push_attempt(params), to: RecordPushAttempt, as: :call
  defdelegate record_attendance(context, params), to: RecordAttendance, as: :call
  defdelegate record_attendance(params), to: RecordAttendance, as: :call
  defdelegate record_communication_message(params), to: RecordCommunicationMessage, as: :call

  defdelegate get_attendance_for_user_class(context, user_id, scheduled_class_id),
    to: GetAttendance,
    as: :for_user_class

  defdelegate get_attendance_for_user_class(user_id, scheduled_class_id),
    to: GetAttendance,
    as: :for_user_class

  defdelegate upsert_exercise_catalog_entry(params), to: UpsertExerciseCatalogEntry, as: :call
  defdelegate analytics_summary(params \\ %{}), to: AnalyticsSummary, as: :call

  @doc """
  Check-ins and attended classes per person and branch since `since`, as
  `{user_id, location_id, check_ins, attended}` (ADR-186 §7).
  """
  def branch_activity(context, %DateTime{} = since),
    do: with_tenant_context(context, fn -> AnalyticsStore.branch_activity(since) end)

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: Palee.Analytics.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)

  # ADR-162: Πρόοδος across providers.
  alias Palee.Analytics.Domain.ProgressFilter

  defdelegate parse_progress_filter(params), to: ProgressFilter, as: :parse
  defdelegate progress_filter_params(filter), to: ProgressFilter, as: :to_params
  defdelegate progress_filter_active_count(filter), to: ProgressFilter, as: :active_count
  defdelegate progress_since(filter, today), to: ProgressFilter, as: :since
  defdelegate progress_weeks(filter, today, first_day), to: ProgressFilter, as: :weeks

  # ADR-165: training load (session RPE, acute:chronic) as an indicator.
  alias Palee.Analytics.Domain.TrainingLoad

  defdelegate training_load(sessions, today), to: TrainingLoad, as: :build
  defdelegate training_load_window_start(today), to: TrainingLoad, as: :window_start
  defdelegate training_load_bands(), to: TrainingLoad, as: :bands
end
