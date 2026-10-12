defmodule MilosTraining.Scheduling.Domain.BookingOperationPolicy do
  @moduledoc """
  Idempotency and conflict rules for offline-replayable booking commands
  (ADR-110). Pure functions: callers load the booking state and apply the
  decision inside their own transaction.

  * A booking request carries a client operation id. Replaying it returns the
    booking it originally created as long as it names the same class;
    reusing the id for another class is a deterministic
    `:idempotency_key_conflict`.
  * An admin resolution may carry a client operation id. A pending booking is
    resolved normally. A booking already resolved *by the same operation*
    with the same outcome is a replay; the same operation id with a different
    outcome is `:idempotency_key_conflict`; anything else stays
    `:booking_not_pending` so the client surfaces the conflict instead of
    replaying it.
  """

  @uuid_pattern ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

  @type resolution_status :: :approved | :rejected

  @spec submission_replay(map(), String.t()) :: :replay | {:error, :idempotency_key_conflict}
  def submission_replay(%{scheduled_class_id: slot_id}, slot_id), do: :replay
  def submission_replay(_existing, _slot_id), do: {:error, :idempotency_key_conflict}

  @spec resolution_decision(map(), resolution_status(), String.t() | nil) ::
          :proceed
          | :replay
          | {:error, :booking_not_pending | :idempotency_key_conflict}
  def resolution_decision(%{status: :pending}, _requested_status, _operation_id), do: :proceed

  def resolution_decision(
        %{resolution_operation_id: operation_id, status: status},
        requested_status,
        operation_id
      )
      when is_binary(operation_id) do
    if status == requested_status,
      do: :replay,
      else: {:error, :idempotency_key_conflict}
  end

  def resolution_decision(_booking, _requested_status, _operation_id),
    do: {:error, :booking_not_pending}

  @doc "Normalizes an optional client operation id; `nil` means not supplied."
  @spec normalize_operation_id(term()) :: {:ok, String.t() | nil} | {:error, list()}
  def normalize_operation_id(nil), do: {:ok, nil}
  def normalize_operation_id(""), do: {:ok, nil}

  def normalize_operation_id(value) when is_binary(value) do
    if Regex.match?(@uuid_pattern, value),
      do: {:ok, String.downcase(value)},
      else: {:error, [client_operation_id: "must be a UUID"]}
  end

  def normalize_operation_id(_value), do: {:error, [client_operation_id: "must be a UUID"]}
end
