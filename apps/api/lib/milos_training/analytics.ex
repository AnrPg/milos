defmodule MilosTraining.Analytics do
  alias MilosTraining.Analytics.Commands.{
    RecordAttendance,
    RecordCommunicationMessage,
    RecordEvent,
    RecordNotificationClick,
    RecordPushAttempt,
    UpsertExerciseCatalogEntry
  }

  alias MilosTraining.Analytics.AnalyticsStore
  alias MilosTraining.Analytics.Domain.{EventCatalog, ExecutionInteraction}
  alias MilosTraining.Analytics.Queries.{AnalyticsSummary, GetAttendance}

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

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Analytics.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
