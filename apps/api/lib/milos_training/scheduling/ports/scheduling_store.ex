defmodule MilosTraining.Scheduling.Ports.SchedulingStore do
  @callback create_class_type(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_class_type(Ecto.UUID.t(), map()) ::
              {:ok, map()}
              | {:error, :not_found | :class_type_archived}
              | {:error, Ecto.Changeset.t()}
  @callback archive_class_type(Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
              {:ok, map()}
              | {:error, :not_found | :class_type_archived | :invalid_class_type_replacement}
              | {:error, {:class_type_replacement_required, non_neg_integer()}}
              | {:error, Ecto.Changeset.t()}
  @callback list_class_types(keyword()) :: [map()]
  @callback get_class_type(Ecto.UUID.t(), keyword()) :: map() | nil
  @callback create_slot(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_slot(Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback delete_slot(Ecto.UUID.t()) ::
              :ok | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  @callback delete_slots_for_workout(Ecto.UUID.t()) ::
              {:ok, [Ecto.UUID.t()]} | {:error, Ecto.Changeset.t()}
  @callback list_workout_change_targets(Ecto.UUID.t()) :: [map()]
  @callback list_slot_ids_for_workout(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  @callback get_slot(Ecto.UUID.t()) :: map() | nil
  @callback list_slots_window(DateTime.t(), DateTime.t(), keyword()) :: [map()]
  @callback get_pending_bookings() :: [map()]
  @callback get_booking(Ecto.UUID.t()) :: map() | nil
  @callback get_booking_execution_access(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback record_attendance(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_attendance_for_user_class(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback get_approved_booking_for_class(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback create_booking(Ecto.UUID.t(), Ecto.UUID.t(), pos_integer()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_approved_booking(Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found | :slot_full}
  @callback approve_booking(Ecto.UUID.t(), String.t() | nil) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found | :booking_not_pending}
  @callback reject_booking(Ecto.UUID.t(), String.t() | nil) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found | :booking_not_pending}
  @callback attach_timeout_job(Ecto.UUID.t(), integer()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback withdraw_booking(Ecto.UUID.t()) ::
              {:ok, map()} | {:error, :not_found | :booking_not_withdrawable}
  @callback cancel_active_future_bookings_for_user(Ecto.UUID.t()) ::
              {:ok, [Ecto.UUID.t()]} | {:error, Ecto.Changeset.t()}
  @callback substitute_slot_workout(Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, map()} | {:error, :not_found}
  @callback count_classes_today() :: non_neg_integer()
end
