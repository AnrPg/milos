defmodule MilosTraining.Scheduling.SchedulingStore do
  @behaviour MilosTraining.Scheduling.Ports.SchedulingStore

  defp adapter do
    Application.fetch_env!(:milos_training, :scheduling_store)
  end

  @impl true
  def create_class_type(params), do: adapter().create_class_type(params)

  @impl true
  def update_class_type(id, params), do: adapter().update_class_type(id, params)

  @impl true
  def archive_class_type(id, replacement_id),
    do: adapter().archive_class_type(id, replacement_id)

  @impl true
  def list_class_types(opts \\ []), do: adapter().list_class_types(opts)

  @impl true
  def get_class_type(id, opts \\ []), do: adapter().get_class_type(id, opts)

  @impl true
  def create_slot(params), do: adapter().create_slot(params)

  @impl true
  def update_slot(id, params), do: adapter().update_slot(id, params)

  @impl true
  def delete_slot(id), do: adapter().delete_slot(id)

  @impl true
  def delete_slots_for_workout(workout_id), do: adapter().delete_slots_for_workout(workout_id)

  @impl true
  def list_workout_change_targets(workout_id),
    do: adapter().list_workout_change_targets(workout_id)

  @impl true
  def list_slot_ids_for_workout(workout_id), do: adapter().list_slot_ids_for_workout(workout_id)

  @impl true
  def get_slot(id), do: adapter().get_slot(id)

  @impl true
  def list_slots_window(start_at, end_at, opts \\ []),
    do: adapter().list_slots_window(start_at, end_at, opts)

  @impl true
  def get_pending_bookings, do: adapter().get_pending_bookings()

  @impl true
  def get_booking(id), do: adapter().get_booking(id)

  @impl true
  def get_booking_execution_access(booking_id, user_id),
    do: adapter().get_booking_execution_access(booking_id, user_id)

  @impl true
  def record_attendance(params), do: adapter().record_attendance(params)

  @impl true
  def get_attendance_for_user_class(user_id, scheduled_class_id),
    do: adapter().get_attendance_for_user_class(user_id, scheduled_class_id)

  @impl true
  def get_approved_booking_for_class(user_id, scheduled_class_id),
    do: adapter().get_approved_booking_for_class(user_id, scheduled_class_id)

  @impl true
  def create_booking(user_id, slot_id, timeout_minutes),
    do: adapter().create_booking(user_id, slot_id, timeout_minutes)

  @impl true
  def create_approved_booking(user_id, slot_id),
    do: adapter().create_approved_booking(user_id, slot_id)

  @impl true
  def approve_booking(id, admin_message), do: adapter().approve_booking(id, admin_message)

  @impl true
  def reject_booking(id, admin_message), do: adapter().reject_booking(id, admin_message)

  @impl true
  def reject_booking_with_reconciliation(id, admin_message, reconciliation),
    do: adapter().reject_booking_with_reconciliation(id, admin_message, reconciliation)

  @impl true
  def attach_timeout_job(booking_id, job_id), do: adapter().attach_timeout_job(booking_id, job_id)

  @impl true
  def withdraw_booking(id), do: adapter().withdraw_booking(id)

  @impl true
  def withdraw_booking_with_reconciliation(id, reconciliation),
    do: adapter().withdraw_booking_with_reconciliation(id, reconciliation)

  @impl true
  def cancel_active_future_bookings_for_user(user_id),
    do: adapter().cancel_active_future_bookings_for_user(user_id)

  @impl true
  def substitute_slot_workout(slot_id, new_workout_id),
    do: adapter().substitute_slot_workout(slot_id, new_workout_id)

  @impl true
  def count_classes_today, do: adapter().count_classes_today()
end
