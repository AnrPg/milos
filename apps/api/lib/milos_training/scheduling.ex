defmodule MilosTraining.Scheduling do
  alias MilosTraining.Scheduling.Commands.{
    ApproveBooking,
    AttachTimeoutJob,
    CancelUserBookingsForRoleTransition,
    CreateSlot,
    DeleteSlotsForWorkout,
    DeleteSlot,
    RecordAttendance,
    RejectBooking,
    SubmitBooking,
    SubmitAutoApprovedBooking,
    UpdateSlot,
    WithdrawBooking
  }

  alias MilosTraining.Scheduling.Queries.{
    GetBooking,
    GetCalendarWeek,
    GetAttendance,
    GetApprovedBookingForClass,
    ListWorkoutChangeTargets,
    GetPendingBookings,
    GetSlot
  }

  defdelegate create_slot(params), to: CreateSlot, as: :call
  defdelegate update_slot(id, params), to: UpdateSlot, as: :call
  defdelegate delete_slot(id), to: DeleteSlot, as: :call
  defdelegate delete_slots_for_workout(workout_id), to: DeleteSlotsForWorkout, as: :call

  defdelegate list_workout_change_targets(workout_id),
    to: ListWorkoutChangeTargets,
    as: :for_workout

  defdelegate list_slot_ids_for_workout(workout_id),
    to: ListWorkoutChangeTargets,
    as: :slot_ids_for_workout

  defdelegate get_slot(id), to: GetSlot, as: :call
  defdelegate get_booking(id), to: GetBooking, as: :call

  def get_booking_execution_access(booking_id, user_id),
    do:
      MilosTraining.Scheduling.SchedulingStore.get_booking_execution_access(
        booking_id,
        user_id
      )

  defdelegate record_attendance(params), to: RecordAttendance, as: :call

  defdelegate get_attendance_for_user_class(user_id, scheduled_class_id),
    to: GetAttendance,
    as: :for_user_class

  defdelegate get_approved_booking_for_class(user_id, scheduled_class_id),
    to: GetApprovedBookingForClass,
    as: :call

  defdelegate get_calendar_week(params), to: GetCalendarWeek, as: :call
  defdelegate get_pending_bookings(), to: GetPendingBookings, as: :call

  defdelegate submit_booking(user_id, slot_id, timeout_minutes), to: SubmitBooking, as: :call

  defdelegate submit_auto_approved_booking(user_id, slot_id),
    to: SubmitAutoApprovedBooking,
    as: :call

  defdelegate approve_booking(id, admin_message), to: ApproveBooking, as: :call
  defdelegate reject_booking(id, admin_message), to: RejectBooking, as: :call
  defdelegate attach_timeout_job(booking_id, job_id), to: AttachTimeoutJob, as: :call
  defdelegate withdraw_booking(id), to: WithdrawBooking, as: :call

  defdelegate cancel_active_future_bookings_for_user(user_id),
    to: CancelUserBookingsForRoleTransition,
    as: :call

  def substitute_slot_workout(slot_id, new_workout_id),
    do: MilosTraining.Scheduling.SchedulingStore.substitute_slot_workout(slot_id, new_workout_id)

  def count_classes_today,
    do: MilosTraining.Scheduling.SchedulingStore.count_classes_today()
end
