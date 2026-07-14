defmodule MilosTraining.Analytics.Queries.GetAttendance do
  alias MilosTraining.Analytics.AnalyticsStore
  alias MilosTraining.Scheduling

  def for_user_class(user_id, scheduled_class_id) do
    Scheduling.get_attendance_for_user_class(user_id, scheduled_class_id) ||
      AnalyticsStore.get_attendance_for_user_class(user_id, scheduled_class_id)
  end
end
