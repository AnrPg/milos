defmodule MilosTraining.Analytics.AnalyticsStore do
  @behaviour MilosTraining.Analytics.Ports.AnalyticsStore

  @default_adapter MilosTraining.Infrastructure.Analytics.EctoAnalyticsStore

  def record_event(params), do: adapter().record_event(params)
  def record_notification_click(params), do: adapter().record_notification_click(params)
  def record_push_attempt(params), do: adapter().record_push_attempt(params)
  def record_attendance(params), do: adapter().record_attendance(params)
  def record_communication_message(params), do: adapter().record_communication_message(params)

  def get_attendance_for_user_class(user_id, scheduled_class_id),
    do: adapter().get_attendance_for_user_class(user_id, scheduled_class_id)

  def upsert_exercise_catalog_entry(params), do: adapter().upsert_exercise_catalog_entry(params)
  def analytics_summary(params), do: adapter().analytics_summary(params)

  defp adapter do
    Application.get_env(:milos_training, :analytics_store, @default_adapter)
  end
end
