defmodule MilosTraining.Application.SubmitBooking do
  require Logger

  alias MilosTraining.Application.AuthorizeFinanceEntitlement
  alias MilosTraining.Scheduling
  alias MilosTraining.Scheduling.Domain.BookingPolicy

  def call(user_id, slot_id) do
    with :ok <- AuthorizeFinanceEntitlement.call(user_id, :class_booking),
         slot when not is_nil(slot) <- Scheduling.get_slot(slot_id),
         :ok <- BookingPolicy.can_book?(slot, user_id: user_id, now: DateTime.utc_now()),
         {:ok, booking} <- create_booking(slot, user_id) do
      dispatch_booking_notification(slot, booking)
      broadcast_booking_event(slot, booking)
      {:ok, booking}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_submission(booking) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "booking:submitted",
      {:booking_submitted, booking}
    )
  end

  defp create_booking(%{auto_approve: true, id: slot_id}, user_id),
    do: Scheduling.submit_auto_approved_booking(user_id, slot_id)

  defp create_booking(slot, user_id),
    do: Scheduling.submit_booking(user_id, slot.id, slot.booking_timeout_minutes)

  defp dispatch_booking_notification(%{auto_approve: true}, booking),
    do: dispatch_non_critical(:booking_resolved, booking)

  defp dispatch_booking_notification(_slot, booking),
    do: dispatch_non_critical(:booking_submitted, booking)

  defp dispatch_non_critical(event, booking) do
    case notification_dispatcher().dispatch_event(event, booking) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "booking_notification_dispatch_failed event=#{event} booking_id=#{booking.id} reason=#{inspect(reason)}"
        )
    end
  rescue
    error ->
      Logger.warning(
        "booking_notification_dispatch_failed event=#{event} booking_id=#{booking.id} reason=#{Exception.message(error)}"
      )
  end

  defp broadcast_booking_event(%{auto_approve: true}, booking) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "booking:resolved",
      {:booking_resolved, booking}
    )
  end

  defp broadcast_booking_event(_slot, booking), do: broadcast_submission(booking)

  defp notification_dispatcher do
    Application.get_env(:milos_training, :notification_dispatcher, MilosTraining.Notifications)
  end
end
