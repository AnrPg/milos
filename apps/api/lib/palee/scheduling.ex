defmodule Palee.Scheduling do
  alias Palee.Scheduling.Commands.{
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
    ResolveBookingOperation,
    SubmitBooking,
    SubmitAutoApprovedBooking,
    TimeoutBooking,
    ArchiveClassType,
    UpdateClassType,
    UpdateSlot,
    WithdrawBooking
  }

  alias Palee.Scheduling.Queries.{
    GetBooking,
    GetBookingByClientOperation,
    GetCalendarWeek,
    GetAttendance,
    GetApprovedBookingForClass,
    GetClassType,
    ListClassTypes,
    ListWorkoutChangeTargets,
    GetPendingBookings,
    GetSlot
  }

  defdelegate transaction(context, fun), to: Palee.Scheduling.SchedulingStore
  defdelegate create_slot(context, params), to: CreateSlot, as: :call
  defdelegate create_slot(params), to: CreateSlot, as: :call
  defdelegate create_class_series(context, params), to: CreateClassSeries, as: :call
  defdelegate create_class_series(params), to: CreateClassSeries, as: :call
  defdelegate extend_class_series(context, series_id, horizon), to: ExtendClassSeries, as: :call

  # ADR-138 D7: class-slot groups.
  def list_active_class_series(%{organization_id: _} = context),
    do: Palee.Scheduling.SchedulingStore.list_active_class_series(context)

  def series_booking_counts(%{organization_id: _} = context, %DateTime{} = since),
    do: Palee.Scheduling.SchedulingStore.series_booking_counts(context, since)

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

  @doc "Past approved bookings of a user, newest first, with class, workout and attendance."
  def list_class_history(context, user_id, opts),
    do: Palee.Scheduling.SchedulingStore.list_class_history(context, user_id, opts)

  def get_booking_execution_access(context, booking_id, user_id),
    do:
      Palee.Scheduling.SchedulingStore.get_booking_execution_access(
        context,
        booking_id,
        user_id
      )

  def get_booking_execution_access(booking_id, user_id),
    do:
      Palee.Scheduling.SchedulingStore.get_booking_execution_access(
        booking_id,
        user_id
      )

  defdelegate record_attendance(context, params), to: RecordAttendance, as: :call
  defdelegate record_attendance(params), to: RecordAttendance, as: :call

  @doc "The member's attendance status per class, for the classes given."
  def list_user_attendance(%{organization_id: _} = context, user_id, slot_ids),
    do: Palee.Scheduling.SchedulingStore.list_user_attendance(context, user_id, slot_ids)

  @doc "ADR-155: one attendance record by id (undoing a scan)."
  def get_attendance(%{organization_id: _} = context, id),
    do: Palee.Scheduling.SchedulingStore.get_attendance(context, id)

  @doc "ADR-155: class check-ins (with a method) since `since`, at a location or anywhere."
  def list_recent_class_check_ins(%{organization_id: _} = context, since, location_id \\ nil),
    do:
      Palee.Scheduling.SchedulingStore.list_recent_class_check_ins(
        context,
        since,
        location_id
      )

  @doc "ADR-155: removes an attendance record (undoing a scan within its minute)."
  def delete_attendance(%{organization_id: _} = context, id),
    do: Palee.Scheduling.SchedulingStore.delete_attendance(context, id)

  defdelegate self_check_in_window(slot), to: Palee.Scheduling.Domain.AttendancePolicy

  defdelegate self_check_in(booking, slot, existing, now),
    to: Palee.Scheduling.Domain.AttendancePolicy

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

  @doc "ADR-120: `opts` may carry `client_operation_id:` for replay dedupe."
  defdelegate submit_booking(context, user_id, slot_id, timeout_minutes, opts),
    to: SubmitBooking,
    as: :call

  defdelegate submit_auto_approved_booking(context, user_id, slot_id),
    to: SubmitAutoApprovedBooking,
    as: :call

  defdelegate submit_auto_approved_booking(context, user_id, slot_id, opts),
    to: SubmitAutoApprovedBooking,
    as: :call

  defdelegate get_booking_by_client_operation(context, user_id, client_operation_id),
    to: GetBookingByClientOperation,
    as: :call

  @doc """
  ADR-120 idempotent admin resolution. `params` holds `:status`
  (`:approved | :rejected`), `:admin_message`, and `:resolution_operation_id`.
  Returns `{:ok, booking, :resolved | :replayed}`.
  """
  defdelegate resolve_booking_operation(context, id, params, reconciliation),
    to: ResolveBookingOperation,
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
  defdelegate timeout_booking(context, booking_id), to: TimeoutBooking, as: :call
  defdelegate timeout_booking(booking_id), to: TimeoutBooking, as: :call

  def withdraw_booking(%{organization_id: _} = context, id),
    do: WithdrawBooking.call(context, id)

  defdelegate withdraw_booking(context, id, reconciliation), to: WithdrawBooking, as: :call

  defdelegate cancel_active_future_bookings_for_user(context, user_id),
    to: CancelUserBookingsForRoleTransition,
    as: :call

  defdelegate cancel_active_future_bookings_for_user(user_id),
    to: CancelUserBookingsForRoleTransition,
    as: :call

  def substitute_slot_workout(context, slot_id, new_workout_id),
    do:
      Palee.Scheduling.SchedulingStore.substitute_slot_workout(
        context,
        slot_id,
        new_workout_id
      )

  def substitute_slot_workout(slot_id, new_workout_id),
    do: Palee.Scheduling.SchedulingStore.substitute_slot_workout(slot_id, new_workout_id)

  def count_classes_today(context),
    do: Palee.Scheduling.SchedulingStore.count_classes_today(context)

  def count_classes_today,
    do: Palee.Scheduling.SchedulingStore.count_classes_today()

  def list_member_slots(context, user_id, start_at, end_at),
    do:
      Palee.Scheduling.SchedulingStore.list_member_slots(
        context,
        user_id,
        start_at,
        end_at
      )

  def list_member_slots(user_id, start_at, end_at),
    do: Palee.Scheduling.SchedulingStore.list_member_slots(user_id, start_at, end_at)

  @doc "WODs classes in [from, to) use, most recently scheduled first."
  def class_workout_usage(%{organization_id: _} = context, from, to, opts \\ []),
    do: Palee.Scheduling.SchedulingStore.class_workout_usage(context, from, to, opts)

  @doc "ADR-176: classes still without a WOD that start in [from, to)."
  def list_slots_missing_workout(%{organization_id: _} = context, from, to),
    do: Palee.Scheduling.SchedulingStore.list_slots_missing_workout(context, from, to)

  defdelegate class_published?(slot),
    to: Palee.Scheduling.Domain.ClassWorkoutReadiness,
    as: :published?

  defdelegate class_workout_status(slot, now, zone),
    to: Palee.Scheduling.Domain.ClassWorkoutReadiness,
    as: :workout_status

  defdelegate class_workout_alert_due(slot, now, zone),
    to: Palee.Scheduling.Domain.ClassWorkoutReadiness,
    as: :alert_due

  def class_workout_alert_horizon_hours,
    do: Palee.Scheduling.Domain.ClassWorkoutReadiness.alert_horizon_hours()

  @doc "Classes of the box in scope among `ids` (any order; missing ids are skipped)."
  def list_slots_by_ids(%{organization_id: _} = context, ids),
    do: Palee.Scheduling.SchedulingStore.list_slots_by_ids(context, ids)

  def get_settings(context), do: Palee.Scheduling.SchedulingStore.get_settings(context)
  def get_settings, do: Palee.Scheduling.SchedulingStore.get_settings()

  def update_settings(context, params),
    do: Palee.Scheduling.SchedulingStore.update_settings(context, params)

  def update_settings(params),
    do: Palee.Scheduling.SchedulingStore.update_settings(params)

  # Phase B (ADR-097): bookings that carry guest and allowance attributes, and waitlists.
  alias Palee.Scheduling.SchedulingStore

  def submit_booking_with(context, user_id, slot_id, timeout_minutes, attrs),
    do: SchedulingStore.create_booking_with(context, user_id, slot_id, timeout_minutes, attrs)

  def submit_auto_approved_booking_with(context, user_id, slot_id, attrs),
    do: SchedulingStore.create_approved_booking_with(context, user_id, slot_id, attrs)

  def join_waitlist(context, user_id, slot_id, attrs),
    do: SchedulingStore.create_waitlisted_booking(context, user_id, slot_id, attrs)

  def list_waitlist(context, slot_id), do: SchedulingStore.list_waitlist(context, slot_id)

  def promote_waitlisted_booking(context, booking_id),
    do: SchedulingStore.promote_waitlisted_booking(context, booking_id)

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: Palee.Scheduling.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
