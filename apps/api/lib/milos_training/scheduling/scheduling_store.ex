defmodule MilosTraining.Scheduling.SchedulingStore do
  @behaviour MilosTraining.Scheduling.Ports.SchedulingStore

  defp adapter do
    Application.fetch_env!(:milos_training, :scheduling_store)
  end

  defp tenant_call(context, function, args) do
    MilosTraining.Infrastructure.Tenancy.RepoContext.run(context, fn ->
      apply(adapter(), function, [context | args])
    end)
  end

  @impl true
  def create_class_type(context, params), do: tenant_call(context, :create_class_type, [params])

  def create_class_type(_params), do: missing_tenant()

  @impl true
  def update_class_type(context, id, params),
    do: tenant_call(context, :update_class_type, [id, params])

  def update_class_type(_id, _params), do: missing_tenant()

  @impl true
  def archive_class_type(context, id, replacement_id),
    do: tenant_call(context, :archive_class_type, [id, replacement_id])

  def archive_class_type(_id, _replacement_id), do: missing_tenant()

  @impl true
  def list_class_types(context, opts), do: tenant_call(context, :list_class_types, [opts])

  def list_class_types(%{organization_id: _} = context), do: list_class_types(context, [])
  def list_class_types(opts) when is_list(opts), do: missing_tenant()
  def list_class_types(), do: missing_tenant()

  @impl true
  def get_class_type(context, id, opts), do: tenant_call(context, :get_class_type, [id, opts])

  def get_class_type(%{organization_id: _} = context, id), do: get_class_type(context, id, [])
  def get_class_type(_id, opts) when is_list(opts), do: missing_tenant()
  def get_class_type(_id), do: missing_tenant()

  @impl true
  def create_slot(context, params), do: tenant_call(context, :create_slot, [params])
  def create_slot(_params), do: missing_tenant()

  @impl true
  def create_class_series(context, params),
    do: tenant_call(context, :create_class_series, [params])

  def create_class_series(_params), do: missing_tenant()

  @impl true
  def extend_class_series(context, series_id, horizon),
    do: tenant_call(context, :extend_class_series, [series_id, horizon])

  def extend_class_series(_series_id, _horizon), do: missing_tenant()

  @impl true
  def update_slot(context, id, params), do: tenant_call(context, :update_slot, [id, params])
  def update_slot(_id, _params), do: missing_tenant()

  @impl true
  def delete_slot(context, id), do: tenant_call(context, :delete_slot, [id])
  def delete_slot(_id), do: missing_tenant()

  @impl true
  def delete_slots_for_workout(context, workout_id),
    do: tenant_call(context, :delete_slots_for_workout, [workout_id])

  def delete_slots_for_workout(_workout_id), do: missing_tenant()

  @impl true
  def delete_class_series_for_workout(context, workout_id),
    do: tenant_call(context, :delete_class_series_for_workout, [workout_id])

  def delete_class_series_for_workout(_workout_id), do: missing_tenant()

  @impl true
  def list_workout_change_targets(context, workout_id),
    do: tenant_call(context, :list_workout_change_targets, [workout_id])

  def list_workout_change_targets(_workout_id), do: missing_tenant()

  @impl true
  def list_slot_ids_for_workout(context, workout_id),
    do: tenant_call(context, :list_slot_ids_for_workout, [workout_id])

  def list_slot_ids_for_workout(_workout_id), do: missing_tenant()

  @impl true
  def get_slot(context, id), do: tenant_call(context, :get_slot, [id])
  def get_slot(_id), do: missing_tenant()

  @impl true
  def list_slots_window(context, start_at, end_at, opts),
    do: tenant_call(context, :list_slots_window, [start_at, end_at, opts])

  def list_slots_window(%{organization_id: _} = context, start_at, end_at),
    do: list_slots_window(context, start_at, end_at, [])

  def list_slots_window(_start_at, _end_at, _opts), do: missing_tenant()

  def list_slots_window(_start_at, _end_at), do: missing_tenant()

  @impl true
  def list_member_slots(context, user_id, start_at, end_at),
    do: tenant_call(context, :list_member_slots, [user_id, start_at, end_at])

  def list_member_slots(_user_id, _start_at, _end_at), do: missing_tenant()

  @impl true
  def get_settings(context), do: tenant_call(context, :get_settings, [])
  def get_settings, do: missing_tenant()

  @impl true
  def update_settings(context, params), do: tenant_call(context, :update_settings, [params])
  def update_settings(_params), do: missing_tenant()

  @impl true
  def get_pending_bookings(context), do: tenant_call(context, :get_pending_bookings, [])
  def get_pending_bookings, do: missing_tenant()

  @impl true
  def get_booking(context, id), do: tenant_call(context, :get_booking, [id])
  def get_booking(_id), do: missing_tenant()

  @impl true
  def get_booking_execution_access(context, booking_id, user_id),
    do: tenant_call(context, :get_booking_execution_access, [booking_id, user_id])

  def get_booking_execution_access(_booking_id, _user_id), do: missing_tenant()

  @impl true
  def record_attendance(context, params), do: tenant_call(context, :record_attendance, [params])
  def record_attendance(_params), do: missing_tenant()

  @impl true
  def get_attendance_for_user_class(context, user_id, scheduled_class_id),
    do: tenant_call(context, :get_attendance_for_user_class, [user_id, scheduled_class_id])

  def get_attendance_for_user_class(_user_id, _scheduled_class_id), do: missing_tenant()

  @impl true
  def get_approved_booking_for_class(context, user_id, scheduled_class_id),
    do: tenant_call(context, :get_approved_booking_for_class, [user_id, scheduled_class_id])

  def get_approved_booking_for_class(_user_id, _scheduled_class_id), do: missing_tenant()

  @impl true
  def create_booking(context, user_id, slot_id, timeout_minutes),
    do: tenant_call(context, :create_booking, [user_id, slot_id, timeout_minutes])

  def create_booking(_user_id, _slot_id, _timeout_minutes), do: missing_tenant()

  @impl true
  def create_approved_booking(context, user_id, slot_id),
    do: tenant_call(context, :create_approved_booking, [user_id, slot_id])

  def create_approved_booking(_user_id, _slot_id), do: missing_tenant()

  @impl true
  def approve_booking(context, id, admin_message),
    do: tenant_call(context, :approve_booking, [id, admin_message])

  def approve_booking(_id, _admin_message), do: missing_tenant()

  @impl true
  def reject_booking(context, id, admin_message),
    do: tenant_call(context, :reject_booking, [id, admin_message])

  def reject_booking(_id, _admin_message), do: missing_tenant()

  @impl true
  def reject_booking_with_reconciliation(context, id, admin_message, reconciliation),
    do:
      tenant_call(context, :reject_booking_with_reconciliation, [
        id,
        admin_message,
        reconciliation
      ])

  def reject_booking_with_reconciliation(_id, _admin_message, _reconciliation),
    do: missing_tenant()

  @impl true
  def attach_timeout_job(context, booking_id, job_id),
    do: tenant_call(context, :attach_timeout_job, [booking_id, job_id])

  def attach_timeout_job(_booking_id, _job_id), do: missing_tenant()

  @impl true
  def timeout_booking(context, id), do: tenant_call(context, :timeout_booking, [id])
  def timeout_booking(_id), do: missing_tenant()

  @impl true
  def withdraw_booking(context, id), do: tenant_call(context, :withdraw_booking, [id])

  @impl true
  def withdraw_booking_with_reconciliation(context, id, reconciliation),
    do: tenant_call(context, :withdraw_booking_with_reconciliation, [id, reconciliation])

  @impl true
  def cancel_active_future_bookings_for_user(context, user_id),
    do: tenant_call(context, :cancel_active_future_bookings_for_user, [user_id])

  def cancel_active_future_bookings_for_user(_user_id), do: missing_tenant()

  @impl true
  def substitute_slot_workout(context, slot_id, new_workout_id),
    do: tenant_call(context, :substitute_slot_workout, [slot_id, new_workout_id])

  def substitute_slot_workout(_slot_id, _new_workout_id), do: missing_tenant()

  @impl true
  def count_classes_today(context), do: tenant_call(context, :count_classes_today, [])
  def count_classes_today, do: missing_tenant()

  defp missing_tenant, do: {:error, :organization_context_required}
end
