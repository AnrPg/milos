defmodule MilosTraining.Scheduling.Ports.SchedulingStore do
  alias MilosTraining.Organizations.TenantContext

  @callback create_class_type(TenantContext.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_class_type(TenantContext.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()}
              | {:error, :not_found | :class_type_archived}
              | {:error, Ecto.Changeset.t()}
  @callback archive_class_type(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
              {:ok, map()}
              | {:error, :not_found | :class_type_archived | :invalid_class_type_replacement}
              | {:error, {:class_type_replacement_required, non_neg_integer()}}
              | {:error, Ecto.Changeset.t()}
  @callback list_class_types(TenantContext.t(), keyword()) :: [map()]
  @callback get_class_type(TenantContext.t(), Ecto.UUID.t(), keyword()) :: map() | nil
  @callback create_slot(TenantContext.t(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_class_series(TenantContext.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback extend_class_series(TenantContext.t(), Ecto.UUID.t(), Date.t()) ::
              {:ok, map()} | {:error, term()}
  @callback update_slot(TenantContext.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback delete_slot(TenantContext.t(), Ecto.UUID.t()) ::
              :ok | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  @callback delete_slots_for_workout(TenantContext.t(), Ecto.UUID.t()) ::
              {:ok, [Ecto.UUID.t()]} | {:error, Ecto.Changeset.t()}
  @callback delete_class_series_for_workout(TenantContext.t(), Ecto.UUID.t()) ::
              :ok | {:error, Ecto.Changeset.t()}
  @callback list_workout_change_targets(TenantContext.t(), Ecto.UUID.t()) :: [map()]
  @callback list_slot_ids_for_workout(TenantContext.t(), Ecto.UUID.t()) :: [Ecto.UUID.t()]
  @callback get_slot(TenantContext.t(), Ecto.UUID.t()) :: map() | nil
  @callback list_slots_window(TenantContext.t(), DateTime.t(), DateTime.t(), keyword()) :: [map()]
  @callback list_member_slots(TenantContext.t(), Ecto.UUID.t(), DateTime.t(), DateTime.t()) :: [
              map()
            ]
  @callback get_settings(TenantContext.t()) :: map()
  @callback update_settings(TenantContext.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_pending_bookings(TenantContext.t()) :: [map()]
  @callback get_booking(TenantContext.t(), Ecto.UUID.t()) :: map() | nil
  @callback get_booking_execution_access(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              map() | nil
  @callback record_attendance(TenantContext.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_attendance_for_user_class(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              map() | nil
  @callback get_approved_booking_for_class(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              map() | nil
  @callback create_booking(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t(), pos_integer()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_approved_booking(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found | :slot_full}
  @callback approve_booking(TenantContext.t(), Ecto.UUID.t(), String.t() | nil) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found | :booking_not_pending}
  @callback reject_booking(TenantContext.t(), Ecto.UUID.t(), String.t() | nil) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found | :booking_not_pending}
  @callback reject_booking_with_reconciliation(
              TenantContext.t(),
              Ecto.UUID.t(),
              String.t() | nil,
              map()
            ) ::
              {:ok, map()} | {:error, term()}
  @callback attach_timeout_job(TenantContext.t(), Ecto.UUID.t(), integer()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback timeout_booking(TenantContext.t(), Ecto.UUID.t()) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found | :booking_not_pending}
  @callback withdraw_booking(TenantContext.t(), Ecto.UUID.t()) ::
              {:ok, map()} | {:error, :not_found | :booking_not_withdrawable}
  @callback withdraw_booking_with_reconciliation(TenantContext.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback cancel_active_future_bookings_for_user(TenantContext.t(), Ecto.UUID.t()) ::
              {:ok, [Ecto.UUID.t()]} | {:error, Ecto.Changeset.t()}
  @callback substitute_slot_workout(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, map()} | {:error, :not_found}
  @callback count_classes_today(TenantContext.t()) :: non_neg_integer()
end
