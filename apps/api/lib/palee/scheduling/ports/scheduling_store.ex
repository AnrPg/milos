defmodule Palee.Scheduling.Ports.SchedulingStore do
  alias Palee.Organizations.TenantContext

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
  @callback transaction(TenantContext.t(), (-> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}
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
  @callback list_slots_by_ids(TenantContext.t(), [Ecto.UUID.t()]) :: [map()]
  @callback list_slots_missing_workout(TenantContext.t(), DateTime.t(), DateTime.t()) :: [map()]
  @callback class_workout_usage(TenantContext.t(), DateTime.t(), DateTime.t(), keyword()) :: [
              %{workout_id: Ecto.UUID.t(), last_scheduled_at: DateTime.t()}
            ]
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
  @callback list_class_history(TenantContext.t(), Ecto.UUID.t(), map()) :: %{
              entries: [map()],
              total: non_neg_integer()
            }
  @callback record_attendance(TenantContext.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback delete_attendance(TenantContext.t(), Ecto.UUID.t()) ::
              {:ok, map()} | {:error, term()}
  @callback get_attendance(TenantContext.t(), Ecto.UUID.t()) :: map() | nil
  @callback list_recent_class_check_ins(TenantContext.t(), DateTime.t(), Ecto.UUID.t() | nil) ::
              [map()]
  @callback list_user_attendance(TenantContext.t(), Ecto.UUID.t(), [Ecto.UUID.t()]) :: map()
  @callback list_class_attendance(TenantContext.t(), [Ecto.UUID.t()]) :: map()
  @callback get_attendance_for_user_class(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              map() | nil
  @callback get_approved_booking_for_class(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              map() | nil
  @callback create_booking(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t(), pos_integer()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_booking(
              TenantContext.t(),
              Ecto.UUID.t(),
              Ecto.UUID.t(),
              pos_integer(),
              keyword()
            ) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback get_booking_by_client_operation(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              map() | nil
  @callback resolve_booking_operation(
              TenantContext.t(),
              Ecto.UUID.t(),
              %{
                required(:status) => :approved | :rejected,
                required(:admin_message) => String.t() | nil,
                required(:resolution_operation_id) => Ecto.UUID.t() | nil
              },
              map() | nil
            ) ::
              {:ok, map(), :resolved | :replayed}
              | {:error, Ecto.Changeset.t()}
              | {:error,
                 :not_found | :booking_not_pending | :slot_full | :idempotency_key_conflict}
  @callback create_approved_booking(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found | :slot_full}
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

  # Phase B (ADR-097)
  @callback create_booking_with(
              TenantContext.t(),
              Ecto.UUID.t(),
              Ecto.UUID.t(),
              pos_integer(),
              map()
            ) ::
              {:ok, map()} | {:error, term()}
  @callback create_approved_booking_with(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback create_waitlisted_booking(TenantContext.t(), Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback list_waitlist(TenantContext.t(), Ecto.UUID.t()) :: [map()]
  @callback promote_waitlisted_booking(TenantContext.t(), Ecto.UUID.t()) ::
              {:ok, map()} | {:error, term()}

  # ADR-138 D7: recurring classes and who books them often.
  @callback list_active_class_series(TenantContext.t()) :: [map()]
  @callback series_booking_counts(TenantContext.t(), DateTime.t()) :: [map()]
end
