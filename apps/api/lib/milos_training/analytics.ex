defmodule MilosTraining.Analytics do
  alias MilosTraining.Analytics.Commands.{
    RecordAttendance,
    RecordCommunicationMessage,
    RecordEvent,
    RecordNotificationClick,
    RecordPushAttempt,
    UpsertExerciseCatalogEntry
  }

  alias MilosTraining.Analytics.Queries.{AnalyticsSummary, GetAttendance}

  defdelegate record_event(params), to: RecordEvent, as: :call
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

  # ADR-099 reviewed tenant export/purge. This context owns its table list and
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
