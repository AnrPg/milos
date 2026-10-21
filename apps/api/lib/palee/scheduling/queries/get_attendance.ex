defmodule Palee.Scheduling.Queries.GetAttendance do
  alias Palee.Scheduling.SchedulingStore

  def for_user_class(context, user_id, scheduled_class_id),
    do: SchedulingStore.get_attendance_for_user_class(context, user_id, scheduled_class_id)

  def for_user_class(user_id, scheduled_class_id),
    do: SchedulingStore.get_attendance_for_user_class(user_id, scheduled_class_id)
end
