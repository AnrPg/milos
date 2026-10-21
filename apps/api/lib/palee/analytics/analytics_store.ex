defmodule Palee.Analytics.AnalyticsStore do
  @behaviour Palee.Analytics.Ports.AnalyticsStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  @default_adapter Palee.Infrastructure.Analytics.EctoAnalyticsStore

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  def record_event(params), do: adapter().record_event(params)
  def record_events(params_list), do: adapter().record_events(params_list)

  def list_recorded_dedupe_keys(event_name, keys),
    do: adapter().list_recorded_dedupe_keys(event_name, keys)

  def list_events_for_source_contexts(event_names, source_context_ids),
    do: adapter().list_events_for_source_contexts(event_names, source_context_ids)

  def record_notification_click(params), do: adapter().record_notification_click(params)
  def record_push_attempt(params), do: adapter().record_push_attempt(params)
  def record_attendance(params), do: adapter().record_attendance(params)
  def record_communication_message(params), do: adapter().record_communication_message(params)

  def get_attendance_for_user_class(user_id, scheduled_class_id),
    do: adapter().get_attendance_for_user_class(user_id, scheduled_class_id)

  def upsert_exercise_catalog_entry(params), do: adapter().upsert_exercise_catalog_entry(params)
  def analytics_summary(params), do: adapter().analytics_summary(params)

  defp adapter do
    Application.get_env(:palee, :analytics_store, @default_adapter)
  end
end
