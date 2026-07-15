defmodule MilosTraining.Application.SubmitBooking do
  require Logger

  alias MilosTraining.{Finance, Identity, Scheduling}
  alias MilosTraining.Scheduling.Domain.BookingPolicy

  def call(%{id: user_id} = actor, slot_id) do
    with slot when not is_nil(slot) <- Scheduling.get_slot(slot_id),
         :ok <- BookingPolicy.can_book?(slot, user_id: user_id, now: DateTime.utc_now()),
         {:ok, reservation} <- reserve_visit(actor, slot) do
      case create_booking(slot, user_id) do
        {:ok, booking} ->
          dispatch_booking_notification(slot, booking)
          broadcast_booking_event(slot, booking)
          broadcast_entitlement_change(user_id)
          {:ok, booking}

        {:error, reason} ->
          release_failed_reservation(reservation)
          {:error, reason}
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      {:error, reason, details} -> {:error, reason, details}
    end
  end

  def call(user_id, slot_id) when is_binary(user_id) do
    case Identity.find_by_id(user_id) do
      nil -> {:error, :not_found}
      actor -> call(actor, slot_id)
    end
  end

  defp reserve_visit(actor, slot) do
    Finance.reserve_entitlement(actor.id, %{
      actor_role: actor.role,
      channel: :in_person,
      capability: :book_classes,
      allowance: :class_visits,
      quantity: 1,
      occurred_on: DateTime.to_date(slot.scheduled_at),
      source_context: "scheduling",
      source_id: slot.id,
      idempotency_key: "booking-reservation:#{Ecto.UUID.generate()}"
    })
  end

  defp release_failed_reservation(%{id: nil}), do: :ok

  defp release_failed_reservation(%{id: reservation_id}) do
    Finance.release_entitlement(reservation_id, %{
      reason: "Scheduling rejected booking creation",
      idempotency_key: "booking-compensation:#{reservation_id}"
    })

    :ok
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

  defp broadcast_entitlement_change(user_id) do
    MilosTraining.Application.BroadcastUserSync.for_user(user_id, ["finance_entitlement"],
      reason: "class_visit_reserved"
    )
  end
end
