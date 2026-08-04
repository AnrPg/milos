defmodule MilosTraining.Scheduling do
  alias MilosTraining.Scheduling.Commands.{
    ApproveBooking,
    AttachTimeoutJob,
    CancelUserBookingsForRoleTransition,
    CreateClassType,
    CreateClassSeries,
    DeleteClassSeriesForWorkout,
    ExtendClassSeries,
    CreateSlot,
    DeleteSlotsForWorkout,
    DeleteSlot,
    RecordAttendance,
    RejectBooking,
    SubmitBooking,
    SubmitAutoApprovedBooking,
    ArchiveClassType,
    UpdateClassType,
    UpdateSlot,
    WithdrawBooking
  }

  alias MilosTraining.Scheduling.Queries.{
    GetBooking,
    GetCalendarWeek,
    GetAttendance,
    GetApprovedBookingForClass,
    GetClassType,
    ListClassTypes,
    ListWorkoutChangeTargets,
    GetPendingBookings,
    GetSlot
  }

  defdelegate create_slot(context, params), to: CreateSlot, as: :call
  defdelegate create_slot(params), to: CreateSlot, as: :call
  defdelegate create_class_series(context, params), to: CreateClassSeries, as: :call
  defdelegate create_class_series(params), to: CreateClassSeries, as: :call
  defdelegate extend_class_series(context, series_id, horizon), to: ExtendClassSeries, as: :call
  defdelegate extend_class_series(series_id, horizon), to: ExtendClassSeries, as: :call
  defdelegate update_slot(context, id, params), to: UpdateSlot, as: :call
  defdelegate update_slot(id, params), to: UpdateSlot, as: :call
  defdelegate delete_slot(context, id), to: DeleteSlot, as: :call
  defdelegate delete_slot(id), to: DeleteSlot, as: :call
  defdelegate delete_slots_for_workout(context, workout_id), to: DeleteSlotsForWorkout, as: :call
  defdelegate delete_slots_for_workout(workout_id), to: DeleteSlotsForWorkout, as: :call

  defdelegate delete_class_series_for_workout(context, workout_id),
    to: DeleteClassSeriesForWorkout,
    as: :call

  defdelegate delete_class_series_for_workout(workout_id),
    to: DeleteClassSeriesForWorkout,
    as: :call

  defdelegate create_class_type(context, params), to: CreateClassType, as: :call
  defdelegate create_class_type(params), to: CreateClassType, as: :call
  defdelegate update_class_type(context, id, params), to: UpdateClassType, as: :call
  defdelegate update_class_type(id, params), to: UpdateClassType, as: :call
  defdelegate archive_class_type(context, id, replacement_id), to: ArchiveClassType, as: :call
  defdelegate archive_class_type(id, replacement_id), to: ArchiveClassType, as: :call
  defdelegate list_class_types(context, opts), to: ListClassTypes, as: :call
  defdelegate list_class_types(context), to: ListClassTypes, as: :call
  defdelegate list_class_types(), to: ListClassTypes, as: :call
  defdelegate get_class_type(context, id, opts), to: GetClassType, as: :call
  defdelegate get_class_type(context, id), to: GetClassType, as: :call
  defdelegate get_class_type(id), to: GetClassType, as: :call

  defdelegate list_workout_change_targets(context, workout_id),
    to: ListWorkoutChangeTargets,
    as: :for_workout

  defdelegate list_workout_change_targets(workout_id),
    to: ListWorkoutChangeTargets,
    as: :for_workout

  defdelegate list_slot_ids_for_workout(context, workout_id),
    to: ListWorkoutChangeTargets,
    as: :slot_ids_for_workout

  defdelegate list_slot_ids_for_workout(workout_id),
    to: ListWorkoutChangeTargets,
    as: :slot_ids_for_workout

  defdelegate get_slot(context, id), to: GetSlot, as: :call
  defdelegate get_slot(id), to: GetSlot, as: :call
  defdelegate get_booking(context, id), to: GetBooking, as: :call
  defdelegate get_booking(id), to: GetBooking, as: :call

  def get_booking_execution_access(context, booking_id, user_id),
    do:
      MilosTraining.Scheduling.SchedulingStore.get_booking_execution_access(
        context,
        booking_id,
        user_id
      )

  def get_booking_execution_access(booking_id, user_id),
    do:
      MilosTraining.Scheduling.SchedulingStore.get_booking_execution_access(
        booking_id,
        user_id
      )

  defdelegate record_attendance(context, params), to: RecordAttendance, as: :call
  defdelegate record_attendance(params), to: RecordAttendance, as: :call

  defdelegate get_attendance_for_user_class(context, user_id, scheduled_class_id),
    to: GetAttendance,
    as: :for_user_class

  defdelegate get_attendance_for_user_class(user_id, scheduled_class_id),
    to: GetAttendance,
    as: :for_user_class

  defdelegate get_approved_booking_for_class(context, user_id, scheduled_class_id),
    to: GetApprovedBookingForClass,
    as: :call

  defdelegate get_approved_booking_for_class(user_id, scheduled_class_id),
    to: GetApprovedBookingForClass,
    as: :call

  defdelegate get_calendar_week(context, params), to: GetCalendarWeek, as: :call
  defdelegate get_calendar_week(params), to: GetCalendarWeek, as: :call
  defdelegate get_pending_bookings(context), to: GetPendingBookings, as: :call
  defdelegate get_pending_bookings(), to: GetPendingBookings, as: :call

  defdelegate submit_booking(context, user_id, slot_id, timeout_minutes),
    to: SubmitBooking,
    as: :call

  defdelegate submit_booking(user_id, slot_id, timeout_minutes), to: SubmitBooking, as: :call

  defdelegate submit_auto_approved_booking(context, user_id, slot_id),
    to: SubmitAutoApprovedBooking,
    as: :call

  defdelegate submit_auto_approved_booking(user_id, slot_id),
    to: SubmitAutoApprovedBooking,
    as: :call

  defdelegate approve_booking(context, id, admin_message), to: ApproveBooking, as: :call
  defdelegate approve_booking(id, admin_message), to: ApproveBooking, as: :call

  def reject_booking(%{organization_id: _} = context, id, admin_message),
    do: RejectBooking.call(context, id, admin_message)

  defdelegate reject_booking(id, admin_message), to: RejectBooking, as: :call

  defdelegate reject_booking(context, id, admin_message, reconciliation),
    to: RejectBooking,
    as: :call

  defdelegate reject_booking(id, admin_message, reconciliation), to: RejectBooking, as: :call
  defdelegate attach_timeout_job(context, booking_id, job_id), to: AttachTimeoutJob, as: :call
  defdelegate attach_timeout_job(booking_id, job_id), to: AttachTimeoutJob, as: :call

  def withdraw_booking(%{organization_id: _} = context, id),
    do: WithdrawBooking.call(context, id)

  defdelegate withdraw_booking(id), to: WithdrawBooking, as: :call
  defdelegate withdraw_booking(context, id, reconciliation), to: WithdrawBooking, as: :call
  defdelegate withdraw_booking(id, reconciliation), to: WithdrawBooking, as: :call

  defdelegate cancel_active_future_bookings_for_user(context, user_id),
    to: CancelUserBookingsForRoleTransition,
    as: :call

  defdelegate cancel_active_future_bookings_for_user(user_id),
    to: CancelUserBookingsForRoleTransition,
    as: :call

  def substitute_slot_workout(context, slot_id, new_workout_id),
    do:
      MilosTraining.Scheduling.SchedulingStore.substitute_slot_workout(
        context,
        slot_id,
        new_workout_id
      )

  def substitute_slot_workout(slot_id, new_workout_id),
    do: MilosTraining.Scheduling.SchedulingStore.substitute_slot_workout(slot_id, new_workout_id)

  def count_classes_today(context),
    do: MilosTraining.Scheduling.SchedulingStore.count_classes_today(context)

  def count_classes_today,
    do: MilosTraining.Scheduling.SchedulingStore.count_classes_today()

  def list_member_slots(context, user_id, start_at, end_at),
    do:
      MilosTraining.Scheduling.SchedulingStore.list_member_slots(
        context,
        user_id,
        start_at,
        end_at
      )

  def list_member_slots(user_id, start_at, end_at),
    do: MilosTraining.Scheduling.SchedulingStore.list_member_slots(user_id, start_at, end_at)

  def get_settings(context), do: MilosTraining.Scheduling.SchedulingStore.get_settings(context)
  def get_settings, do: MilosTraining.Scheduling.SchedulingStore.get_settings()

  def update_settings(context, params),
    do: MilosTraining.Scheduling.SchedulingStore.update_settings(context, params)

  def update_settings(params),
    do: MilosTraining.Scheduling.SchedulingStore.update_settings(params)
end
