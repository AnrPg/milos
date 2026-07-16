defmodule MilosTraining.Application.ResolveBooking do
  alias MilosTraining.{Finance, Scheduling}

  def call(booking_id, params) do
    action = Map.get(params, :action) || Map.get(params, "action")
    admin_message = Map.get(params, :admin_message) || Map.get(params, "admin_message")

    with booking when not is_nil(booking) <- Scheduling.get_booking(booking_id),
         {:ok, updated_booking} <- run_resolution(action, booking_id, admin_message) do
      maybe_reconcile_now(action, updated_booking)
      MilosTraining.Notifications.dispatch_event(:booking_resolved, updated_booking)
      broadcast_resolution(updated_booking)
      {:ok, updated_booking}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :bad_request}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_resolution(:approve, booking_id, admin_message),
    do: Scheduling.approve_booking(booking_id, admin_message)

  defp run_resolution("approve", booking_id, admin_message),
    do: run_resolution(:approve, booking_id, admin_message)

  defp run_resolution(:reject, booking_id, admin_message),
    do:
      Scheduling.reject_booking(
        booking_id,
        admin_message,
        reconciliation("Booking rejected", "booking-rejected", booking_id)
      )

  defp run_resolution("reject", booking_id, admin_message),
    do: run_resolution(:reject, booking_id, admin_message)

  defp run_resolution(_, _booking_id, _admin_message), do: :error

  defp reconciliation(reason, idempotency_prefix, booking_id) do
    booking = Scheduling.get_booking(booking_id)

    %{
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

  defp broadcast_resolution(booking) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "booking:resolved",
      {:booking_resolved, booking}
    )
  end
end
