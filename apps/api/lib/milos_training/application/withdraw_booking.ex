defmodule MilosTraining.Application.WithdrawBooking do
  alias MilosTraining.Application.{BookingEntitlement, BookingTerms, PromoteClassWaitlist}
  alias MilosTraining.{Finance, Notifications, Scheduling}
  alias MilosTraining.Scheduling.Domain.BookingPolicy

  def call(context, user_id, booking_id) do
    with booking when not is_nil(booking) <- Scheduling.get_booking(context, booking_id),
         :ok <- verify_ownership(booking, user_id),
         late? = late_cancellation?(context, booking),
         {:ok, withdrawn_booking} <-
           Scheduling.withdraw_booking(context, booking_id, reconciliation(booking, late?)) do
      reconcile_now(booking, late?)
      PromoteClassWaitlist.call(context, booking.scheduled_class_id)
      {:ok, Map.put(withdrawn_booking, :late_cancellation, late?)}
    else
      nil -> {:error, :not_found}
      {:error, :not_owner} -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_ownership(%{user_id: uid}, user_id) when uid == user_id, do: :ok
  defp verify_ownership(_, _), do: {:error, :not_owner}

  # ADR-097: withdrawing an approved booking inside the cancellation cutoff
  # consumes the visit instead of returning it.
  defp late_cancellation?(
         context,
         %{scheduled_class: %{scheduled_at: scheduled_at} = slot} = booking
       ) do
    terms = BookingTerms.for_slot(context, booking.user_id, slot)

    BookingPolicy.late_cancellation?(
      booking.status,
      scheduled_at,
      DateTime.utc_now(),
      terms.cancellation_cutoff_hours
    )
  end

  defp late_cancellation?(_context, _booking), do: false

  defp reconciliation(%{status: :waitlisted}, _late?), do: nil

  defp reconciliation(booking, late?) do
    %{
      organization_id: booking.organization_id,
      booking_id: booking.id,
      user_id: booking.user_id,
      scheduled_class_id: booking.scheduled_class_id,
      allowance: Atom.to_string(BookingEntitlement.allowance(booking)),
      finalize: late?,
      reason: reason(late?),
      idempotency_key: "booking-withdrawn:#{booking.id}",
      delete_pending_notification: true
    }
  end

  defp reconcile_now(%{status: :waitlisted}, _late?), do: :ok

  defp reconcile_now(booking, late?) do
    params = %{reason: reason(late?), idempotency_key: "booking-withdrawn:#{booking.id}"}
    allowance = BookingEntitlement.allowance(booking)

    _result =
      if late?,
        do:
          Finance.finalize_entitlement_source(
            booking.user_id,
            "scheduling",
            booking.scheduled_class_id,
            allowance,
            params
          ),
        else:
          Finance.release_entitlement_source(
            booking.user_id,
            "scheduling",
            booking.scheduled_class_id,
            allowance,
            params
          )

    _result = Notifications.delete_booking_pending_notifications(booking.id)
    :ok
  end

  defp reason(true), do: "Late cancellation"
  defp reason(false), do: "Booking withdrawn"
end
