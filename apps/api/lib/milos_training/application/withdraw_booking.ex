defmodule MilosTraining.Application.WithdrawBooking do
  require Logger

  alias MilosTraining.{Finance, Scheduling}
  alias MilosTraining.Notifications

  def call(user_id, booking_id) do
    with booking when not is_nil(booking) <- Scheduling.get_booking(booking_id),
         :ok <- verify_ownership(booking, user_id),
         {:ok, withdrawn_booking} <- Scheduling.withdraw_booking(booking_id) do
      delete_booking_pending_notifications(booking_id)
      release_visit(booking)
      {:ok, withdrawn_booking}
    else
      nil -> {:error, :not_found}
      {:error, :not_owner} -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_ownership(%{user_id: uid}, user_id) when uid == user_id, do: :ok
  defp verify_ownership(_, _), do: {:error, :not_owner}

  defp release_visit(booking) do
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
  end

  # Hard-delete the booking_pending admin notifications that were created when
  # the user submitted the booking — they are no longer actionable after withdrawal.
  defp delete_booking_pending_notifications(booking_id) do
    case Notifications.delete_booking_pending_notifications(booking_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Could not delete booking_pending notifications for booking_id=#{booking_id}: #{inspect(reason)}"
        )
    end
  end
end
