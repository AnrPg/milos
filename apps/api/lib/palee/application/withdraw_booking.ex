defmodule Palee.Application.WithdrawBooking do
  alias Palee.Application.{
    BookingEntitlement,
    BookingTerms,
    PromoteClassWaitlist,
    TrackAnalyticsEvent
  }

  alias Palee.{Notifications, Scheduling}
  alias Palee.Scheduling.Domain.BookingPolicy

  def call(context, user_id, booking_id) do
    with booking when not is_nil(booking) <- Scheduling.get_booking(context, booking_id),
         :ok <- verify_ownership(booking, user_id),
         late? = late_cancellation?(context, booking),
         {:ok, withdrawn_booking} <-
           Scheduling.withdraw_booking(context, booking_id, reconciliation(booking, late?)) do
      reconcile_now(context, booking, late?)
      PromoteClassWaitlist.call(context, booking.scheduled_class_id)

      Palee.DomainEvents.publish(:booking_cancelled, %{
        organization_id: booking.organization_id,
        booking_id: booking.id,
        user_id: booking.user_id,
        kind: Map.get(booking, :kind, "member"),
        by: :member,
        at: DateTime.utc_now()
      })

      TrackAnalyticsEvent.call("class_booking_cancelled", context, withdrawn_booking, %{
        metadata: %{
          cancelled_by: "member",
          previous_status: booking.status,
          late_cancellation: late?
        }
      })

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

  @doc """
  The durable release of a withdrawn booking's visit, written with the
  withdrawal (nil for a waitlist place, which holds no visit). A cancelled
  class (ADR-200) releases its bookings the same way, never as late.
  """
  def reconciliation(booking, late?, reason \\ nil)

  def reconciliation(%{status: :waitlisted}, _late?, _reason), do: nil

  def reconciliation(booking, late?, reason) do
    %{
      organization_id: booking.organization_id,
      booking_id: booking.id,
      user_id: booking.user_id,
      scheduled_class_id: booking.scheduled_class_id,
      allowance: Atom.to_string(BookingEntitlement.allowance(booking)),
      finalize: late?,
      reason: reason || reason(late?),
      idempotency_key: "booking-withdrawn:#{booking.id}",
      delete_pending_notification: true
    }
  end

  @doc "Returns (or consumes) the visit right away; the durable job is the fallback."
  def reconcile_now(context, booking, late?, reason \\ nil)

  def reconcile_now(_context, %{status: :waitlisted}, _late?, _reason), do: :ok

  # TD-092: the ledger transition runs in the tenant's scope and the staff's
  # pending-booking notifications are removed in each recipient's scope -
  # unscoped, RLS hid both and the visit was silently never returned.
  def reconcile_now(context, booking, late?, reason) do
    params = %{
      reason: reason || reason(late?),
      idempotency_key: "booking-withdrawn:#{booking.id}"
    }

    allowance = BookingEntitlement.allowance(booking)

    _result =
      if late?,
        do:
          BookingEntitlement.finalize(
            context,
            booking.user_id,
            booking.scheduled_class_id,
            allowance,
            params
          ),
        else:
          BookingEntitlement.release(
            context,
            booking.user_id,
            booking.scheduled_class_id,
            allowance,
            params
          )

    _result =
      Notifications.delete_booking_pending_notifications(booking.organization_id, booking.id)

    :ok
  end

  defp reason(true), do: "Late cancellation"
  defp reason(false), do: "Booking withdrawn"
end
