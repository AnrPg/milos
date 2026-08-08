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

  def create_class_type(params), do: create_class_type(legacy_scope(), params)

  @impl true
  def update_class_type(context, id, params),
    do: tenant_call(context, :update_class_type, [id, params])

  def update_class_type(id, params), do: update_class_type(legacy_scope(), id, params)

  @impl true
  def archive_class_type(context, id, replacement_id),
    do: tenant_call(context, :archive_class_type, [id, replacement_id])

  def archive_class_type(id, replacement_id),
    do: archive_class_type(legacy_scope(), id, replacement_id)

  @impl true
  def list_class_types(context, opts), do: tenant_call(context, :list_class_types, [opts])

  def list_class_types(%{organization_id: _} = context), do: list_class_types(context, [])
  def list_class_types(opts) when is_list(opts), do: list_class_types(legacy_scope(), opts)
  def list_class_types(), do: list_class_types(legacy_scope(), [])

  @impl true
  def get_class_type(context, id, opts), do: tenant_call(context, :get_class_type, [id, opts])

  def get_class_type(%{organization_id: _} = context, id), do: get_class_type(context, id, [])
  def get_class_type(id, opts) when is_list(opts), do: get_class_type(legacy_scope(), id, opts)
  def get_class_type(id), do: get_class_type(legacy_scope(), id, [])

  defp legacy_scope do
    organization =
      MilosTraining.Organizations.get_by_slug(
        MilosTraining.Organizations.legacy_organization_slug()
      )

    %{organization_id: organization.id}
  end

  @impl true
  def create_slot(context, params), do: tenant_call(context, :create_slot, [params])
  def create_slot(params), do: create_slot(legacy_scope(), params)

  @impl true
  def create_class_series(context, params),
    do: tenant_call(context, :create_class_series, [params])

  def create_class_series(params), do: create_class_series(legacy_scope(), params)

  @impl true
  def extend_class_series(context, series_id, horizon),
    do: tenant_call(context, :extend_class_series, [series_id, horizon])

  def extend_class_series(series_id, horizon),
    do: extend_class_series(legacy_scope(), series_id, horizon)

  @impl true
  def update_slot(context, id, params), do: tenant_call(context, :update_slot, [id, params])
  def update_slot(id, params), do: update_slot(legacy_scope(), id, params)

  @impl true
  def delete_slot(context, id), do: tenant_call(context, :delete_slot, [id])
  def delete_slot(id), do: delete_slot(legacy_scope(), id)

  @impl true
  def delete_slots_for_workout(context, workout_id),
    do: tenant_call(context, :delete_slots_for_workout, [workout_id])

  def delete_slots_for_workout(workout_id),
    do: delete_slots_for_workout(legacy_scope(), workout_id)

  @impl true
  def delete_class_series_for_workout(context, workout_id),
    do: tenant_call(context, :delete_class_series_for_workout, [workout_id])

  def delete_class_series_for_workout(workout_id),
    do: delete_class_series_for_workout(legacy_scope(), workout_id)

  @impl true
  def list_workout_change_targets(context, workout_id),
    do: tenant_call(context, :list_workout_change_targets, [workout_id])

  def list_workout_change_targets(workout_id),
    do: list_workout_change_targets(legacy_scope(), workout_id)

  @impl true
  def list_slot_ids_for_workout(context, workout_id),
    do: tenant_call(context, :list_slot_ids_for_workout, [workout_id])

  def list_slot_ids_for_workout(workout_id),
    do: list_slot_ids_for_workout(legacy_scope(), workout_id)

  @impl true
  def get_slot(context, id), do: tenant_call(context, :get_slot, [id])
  def get_slot(id), do: get_slot(legacy_scope(), id)

  @impl true
  def list_slots_window(context, start_at, end_at, opts),
    do: tenant_call(context, :list_slots_window, [start_at, end_at, opts])

  def list_slots_window(%{organization_id: _} = context, start_at, end_at),
    do: list_slots_window(context, start_at, end_at, [])

  def list_slots_window(start_at, end_at, opts),
    do: list_slots_window(legacy_scope(), start_at, end_at, opts)

  def list_slots_window(start_at, end_at),
    do: list_slots_window(legacy_scope(), start_at, end_at, [])

  @impl true
  def list_member_slots(context, user_id, start_at, end_at),
    do: tenant_call(context, :list_member_slots, [user_id, start_at, end_at])

  def list_member_slots(user_id, start_at, end_at),
    do: list_member_slots(legacy_scope(), user_id, start_at, end_at)

  @impl true
  def get_settings(context), do: tenant_call(context, :get_settings, [])
  def get_settings, do: get_settings(legacy_scope())

  @impl true
  def update_settings(context, params), do: tenant_call(context, :update_settings, [params])
  def update_settings(params), do: update_settings(legacy_scope(), params)

  @impl true
  def get_pending_bookings(context), do: tenant_call(context, :get_pending_bookings, [])
  def get_pending_bookings, do: get_pending_bookings(legacy_scope())

  @impl true
  def get_booking(context, id), do: tenant_call(context, :get_booking, [id])
  def get_booking(id), do: get_booking(legacy_scope(), id)

  @impl true
  def get_booking_execution_access(context, booking_id, user_id),
    do: tenant_call(context, :get_booking_execution_access, [booking_id, user_id])

  def get_booking_execution_access(booking_id, user_id),
    do: get_booking_execution_access(legacy_scope(), booking_id, user_id)

  @impl true
  def record_attendance(context, params), do: tenant_call(context, :record_attendance, [params])
  def record_attendance(params), do: record_attendance(legacy_scope(), params)

  @impl true
  def get_attendance_for_user_class(context, user_id, scheduled_class_id),
    do: tenant_call(context, :get_attendance_for_user_class, [user_id, scheduled_class_id])

  def get_attendance_for_user_class(user_id, scheduled_class_id),
    do: get_attendance_for_user_class(legacy_scope(), user_id, scheduled_class_id)

  @impl true
  def get_approved_booking_for_class(context, user_id, scheduled_class_id),
    do: tenant_call(context, :get_approved_booking_for_class, [user_id, scheduled_class_id])

  def get_approved_booking_for_class(user_id, scheduled_class_id),
    do: get_approved_booking_for_class(legacy_scope(), user_id, scheduled_class_id)

  @impl true
  def create_booking(context, user_id, slot_id, timeout_minutes),
    do: tenant_call(context, :create_booking, [user_id, slot_id, timeout_minutes])

  def create_booking(user_id, slot_id, timeout_minutes),
    do: create_booking(legacy_scope(), user_id, slot_id, timeout_minutes)

  @impl true
  def create_approved_booking(context, user_id, slot_id),
    do: tenant_call(context, :create_approved_booking, [user_id, slot_id])

  def create_approved_booking(user_id, slot_id),
    do: create_approved_booking(legacy_scope(), user_id, slot_id)

  @impl true
  def approve_booking(context, id, admin_message),
    do: tenant_call(context, :approve_booking, [id, admin_message])

  def approve_booking(id, admin_message), do: approve_booking(legacy_scope(), id, admin_message)

  @impl true
  def reject_booking(context, id, admin_message),
    do: tenant_call(context, :reject_booking, [id, admin_message])

  def reject_booking(id, admin_message), do: reject_booking(legacy_scope(), id, admin_message)

  @impl true
  def reject_booking_with_reconciliation(context, id, admin_message, reconciliation),
    do:
      tenant_call(context, :reject_booking_with_reconciliation, [
        id,
        admin_message,
        reconciliation
      ])

  def reject_booking_with_reconciliation(id, admin_message, reconciliation),
    do: reject_booking_with_reconciliation(legacy_scope(), id, admin_message, reconciliation)

  @impl true
  def attach_timeout_job(context, booking_id, job_id),
    do: tenant_call(context, :attach_timeout_job, [booking_id, job_id])

  def attach_timeout_job(booking_id, job_id),
    do: attach_timeout_job(legacy_scope(), booking_id, job_id)

  @impl true
  def timeout_booking(context, id), do: tenant_call(context, :timeout_booking, [id])
  def timeout_booking(id), do: timeout_booking(legacy_scope(), id)

  @impl true
  def withdraw_booking(context, id), do: tenant_call(context, :withdraw_booking, [id])

  @impl true
  def withdraw_booking_with_reconciliation(context, id, reconciliation),
    do: tenant_call(context, :withdraw_booking_with_reconciliation, [id, reconciliation])

  @impl true
  def cancel_active_future_bookings_for_user(context, user_id),
    do: tenant_call(context, :cancel_active_future_bookings_for_user, [user_id])

  def cancel_active_future_bookings_for_user(user_id),
    do: cancel_active_future_bookings_for_user(legacy_scope(), user_id)

  @impl true
  def substitute_slot_workout(context, slot_id, new_workout_id),
    do: tenant_call(context, :substitute_slot_workout, [slot_id, new_workout_id])

  def substitute_slot_workout(slot_id, new_workout_id),
    do: substitute_slot_workout(legacy_scope(), slot_id, new_workout_id)

  @impl true
  def count_classes_today(context), do: tenant_call(context, :count_classes_today, [])
  def count_classes_today, do: count_classes_today(legacy_scope())
end
