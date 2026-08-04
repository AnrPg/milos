defmodule MilosTraining.Application.ResolveBooking do
  alias MilosTraining.Application.ScheduleRealtime
  alias MilosTraining.{Finance, Scheduling}

  def call(context, booking_id, params) do
    action = Map.get(params, :action) || Map.get(params, "action")
    admin_message = Map.get(params, :admin_message) || Map.get(params, "admin_message")

    with booking when not is_nil(booking) <- Scheduling.get_booking(context, booking_id),
         {:ok, updated_booking} <- run_resolution(context, action, booking_id, admin_message) do
      maybe_reconcile_now(action, updated_booking)

      notification_payload =
        updated_booking
        |> plain_map()
        |> Map.put(:notification_batch_at, DateTime.utc_now() |> DateTime.truncate(:second))

      MilosTraining.Notifications.dispatch_event(:booking_resolved, notification_payload)
      broadcast_resolution(updated_booking)
      {:ok, updated_booking}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :bad_request}
      {:error, reason} -> {:error, reason}
    end
  end

  def call(booking_id, params), do: call(nil, booking_id, params)

  defp run_resolution(nil, :approve, booking_id, admin_message),
    do: Scheduling.approve_booking(booking_id, admin_message)

  defp run_resolution(context, :approve, booking_id, admin_message),
    do: Scheduling.approve_booking(context, booking_id, admin_message)

  defp run_resolution(context, "approve", booking_id, admin_message),
    do: run_resolution(context, :approve, booking_id, admin_message)

  defp run_resolution(nil, :reject, booking_id, admin_message),
    do:
      Scheduling.reject_booking(
        booking_id,
        admin_message,
        reconciliation(nil, "Booking rejected", "booking-rejected", booking_id)
      )

  defp run_resolution(context, :reject, booking_id, admin_message),
    do:
      Scheduling.reject_booking(
        context,
        booking_id,
        admin_message,
        reconciliation(context, "Booking rejected", "booking-rejected", booking_id)
      )

  defp run_resolution(context, "reject", booking_id, admin_message),
    do: run_resolution(context, :reject, booking_id, admin_message)

  defp run_resolution(_context, _, _booking_id, _admin_message), do: :error

  defp reconciliation(nil, reason, idempotency_prefix, booking_id) do
    booking = Scheduling.get_booking(booking_id)

    reconciliation_payload(booking, reason, idempotency_prefix)
  end

  defp reconciliation(context, reason, idempotency_prefix, booking_id) do
    booking = Scheduling.get_booking(context, booking_id)

    reconciliation_payload(booking, reason, idempotency_prefix)
  end

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

  defp maybe_reconcile_now(action, booking) when action in [:reject, "reject"] do
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

  defp maybe_reconcile_now(_action, _booking), do: :ok

  defp plain_map(%_{} = struct), do: Map.from_struct(struct)
  defp plain_map(map) when is_map(map), do: map

  defp broadcast_resolution(booking) do
    ScheduleRealtime.broadcast("booking_resolved", booking)
  end
end
