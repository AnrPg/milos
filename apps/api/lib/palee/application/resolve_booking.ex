defmodule Palee.Application.ResolveBooking do
  alias Palee.Application.{
    BookingEntitlement,
    PromoteClassWaitlist,
    ScheduleRealtime,
    TrackAnalyticsEvent
  }

  alias Palee.Scheduling
  alias Palee.Scheduling.Domain.BookingOperationPolicy

  @doc """
  Approves or rejects a pending booking.

  Accepts an optional `client_operation_id` (ADR-120). Returns
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
      if outcome == :resolved, do: announce(context, status, updated_booking, admin_message)
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

  defp resolution_event(:approved), do: "class_booking_approved"
  defp resolution_event(:rejected), do: "class_booking_rejected"

  defp announce(context, status, booking, admin_message) do
    maybe_reconcile_now(context, status, booking)

    if status == :rejected,
      do: PromoteClassWaitlist.call(context, booking.scheduled_class_id)

    notification_payload =
      booking
      |> plain_map()
      |> Map.put(:notification_batch_at, DateTime.utc_now() |> DateTime.truncate(:second))

    Palee.Notifications.dispatch_event(:booking_resolved, notification_payload)
    broadcast_resolution(booking)

    TrackAnalyticsEvent.call(resolution_event(status), context, booking, %{
      metadata: %{
        member_id: booking.user_id,
        has_admin_message: admin_message not in [nil, ""]
      }
    })
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
      allowance: Atom.to_string(BookingEntitlement.allowance(booking)),
      reason: reason,
      idempotency_key: "#{idempotency_prefix}:#{booking.id}"
    }
  end

  # TD-092: the release runs in the tenant's scope - unscoped, RLS hid the
  # reservation and the visit was silently never returned.
  defp maybe_reconcile_now(context, :rejected, booking) do
    _result =
      BookingEntitlement.release(
        context,
        booking.user_id,
        booking.scheduled_class_id,
        BookingEntitlement.allowance(booking),
        %{
          reason: "Booking rejected",
          idempotency_key: "booking-rejected:#{booking.id}"
        }
      )

    :ok
  end

  defp maybe_reconcile_now(_context, _status, _booking), do: :ok

  defp plain_map(%_{} = struct), do: Map.from_struct(struct)
  defp plain_map(map) when is_map(map), do: map

  defp broadcast_resolution(booking) do
    ScheduleRealtime.broadcast("booking_resolved", booking)
  end
end
