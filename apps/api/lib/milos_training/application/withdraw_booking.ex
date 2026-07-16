defmodule MilosTraining.Application.WithdrawBooking do
  alias MilosTraining.{Finance, Notifications, Scheduling}

  def call(user_id, booking_id) do
    with booking when not is_nil(booking) <- Scheduling.get_booking(booking_id),
         :ok <- verify_ownership(booking, user_id),
         {:ok, withdrawn_booking} <-
           Scheduling.withdraw_booking(booking_id, reconciliation(booking)) do
      reconcile_now(booking)
      {:ok, withdrawn_booking}
    else
      nil -> {:error, :not_found}
      {:error, :not_owner} -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_ownership(%{user_id: uid}, user_id) when uid == user_id, do: :ok
  defp verify_ownership(_, _), do: {:error, :not_owner}

  defp reconciliation(booking) do
    %{
      booking_id: booking.id,
      user_id: booking.user_id,
      scheduled_class_id: booking.scheduled_class_id,
      reason: "Booking withdrawn",
      idempotency_key: "booking-withdrawn:#{booking.id}",
      delete_pending_notification: true
    }
  end

  defp reconcile_now(booking) do
    _result =
      Finance.release_entitlement_source(
        booking.user_id,
        "scheduling",
        booking.scheduled_class_id,
        :class_visits,
        %{
          reason: "Booking withdrawn",
          idempotency_key: "booking-withdrawn:#{booking.id}"
        }
      )

    _result = Notifications.delete_booking_pending_notifications(booking.id)
    :ok
  end
end
