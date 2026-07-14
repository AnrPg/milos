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
  defdelegate record_attendance(params), to: RecordAttendance, as: :call
  defdelegate record_communication_message(params), to: RecordCommunicationMessage, as: :call

  defdelegate get_attendance_for_user_class(user_id, scheduled_class_id),
    to: GetAttendance,
    as: :for_user_class

  defdelegate upsert_exercise_catalog_entry(params), to: UpsertExerciseCatalogEntry, as: :call
  defdelegate analytics_summary(params \\ %{}), to: AnalyticsSummary, as: :call
end
