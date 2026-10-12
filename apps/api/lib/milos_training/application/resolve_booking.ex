defmodule MilosTraining.Application.ResolveBooking do
  alias MilosTraining.Application.ScheduleRealtime
  alias MilosTraining.{Finance, Scheduling}
  alias MilosTraining.Scheduling.Domain.BookingOperationPolicy

  @doc """
  Approves or rejects a pending booking.

  Accepts an optional `client_operation_id` (ADR-102). Returns
  `{:ok, booking, :resolved | :replayed}`; a replay of the operation that
  already resolved the booking returns it without notifying the member,
  releasing entitlements, or broadcasting again. Bookings resolved by anything
  else stay a deterministic `:booking_not_pending` conflict.
  """
  def call(context, booking_id, params) do
    action = Map.get(params, :action) || Map.get(params, "action")
    admin_message = Map.get(params, :admin_message) || Map.get(params, "admin_message")

    operation_id =
      Map.get(params, :client_operation_id) || Map.get(params, "client_operation_id")

    with {:ok, status} <- requested_status(action),
         {:ok, operation_id} <- BookingOperationPolicy.normalize_operation_id(operation_id),
         booking when is_map(booking) <- Scheduling.get_booking(context, booking_id),
         {:ok, updated_booking, outcome} <-
           Scheduling.resolve_booking_operation(
             context,
             booking_id,
             %{
               status: status,
               admin_message: admin_message,
               resolution_operation_id: operation_id
             },
             reconciliation_for(status, booking)
           ) do
      if outcome == :resolved, do: announce(status, updated_booking)
      {:ok, updated_booking, outcome}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :bad_request}
      {:error, reason} -> {:error, reason}
    end
  end

  def call(_booking_id, _params), do: {:error, :organization_context_required}

  defp requested_status(action) when action in [:approve, "approve"], do: {:ok, :approved}
  defp requested_status(action) when action in [:reject, "reject"], do: {:ok, :rejected}
  defp requested_status(_action), do: :error

  defp announce(status, booking) do
    maybe_reconcile_now(status, booking)

    notification_payload =
      booking
      |> plain_map()
      |> Map.put(:notification_batch_at, DateTime.utc_now() |> DateTime.truncate(:second))

    MilosTraining.Notifications.dispatch_event(:booking_resolved, notification_payload)
    broadcast_resolution(booking)
  end

  defp reconciliation_for(:rejected, booking),
    do: reconciliation_payload(booking, "Booking rejected", "booking-rejected")

  defp reconciliation_for(_status, _booking), do: nil

  defp reconciliation_payload(booking, reason, idempotency_prefix) do
    %{
      organization_id: booking.organization_id,
      booking_id: booking.id,
      user_id: booking.user_id,
      scheduled_class_id: booking.scheduled_class_id,
      reason: reason,
      idempotency_key: "#{idempotency_prefix}:#{booking.id}"
    }
  end

  defp maybe_reconcile_now(:rejected, booking) do
    _result =
      Finance.release_entitlement_source(
        booking.user_id,
        "scheduling",
        booking.scheduled_class_id,
        :class_visits,
        %{
          reason: "Booking rejected",
          idempotency_key: "booking-rejected:#{booking.id}"
        }
      )

    :ok
  end

  defp maybe_reconcile_now(_status, _booking), do: :ok

  defp plain_map(%_{} = struct), do: Map.from_struct(struct)
  defp plain_map(map) when is_map(map), do: map

  defp broadcast_resolution(booking) do
    ScheduleRealtime.broadcast("booking_resolved", booking)
  end
end
