defmodule Palee.Application.PromoteClassWaitlist do
  @moduledoc """
  Fills freed capacity from a class waitlist (ADR-097): entries are tried in
  priority order; each promotion reserves the member's allowance through the
  normal booking saga, and entries whose package no longer allows the class are
  skipped. Promoted members are notified.
  """

  require Logger

  alias Palee.Application.{BookingEntitlement, ScheduleRealtime, SubmitBooking}
  alias Palee.{Identity, Notifications, Scheduling}
  alias Palee.Scheduling.Domain.BookingPolicy

  def call(nil, _slot_id), do: :ok

  def call(context, slot_id) do
    case Scheduling.get_slot(context, slot_id) do
      nil ->
        :ok

      slot ->
        # A paused or cancelled class promotes nobody (ADR-200 §2).
        if DateTime.compare(slot.scheduled_at, DateTime.utc_now()) == :gt and
             is_nil(BookingPolicy.closed_reason(slot)) and
             not BookingPolicy.slot_full?(slot) do
          context
          |> Scheduling.list_waitlist(slot.id)
          |> BookingPolicy.waitlist_order()
          |> promote_first(context, slot)
        else
          :ok
        end
    end
  end

  defp promote_first([], _context, _slot), do: :ok

  defp promote_first([entry | rest], context, slot) do
    case promote(context, slot, entry) do
      {:ok, booking} ->
        notify(slot, booking)
        # More capacity may still be free (for example after a capacity increase).
        call(context, slot.id)

      {:error, reason} ->
        Logger.info("waitlist_entry_skipped booking_id=#{entry.id} reason=#{inspect(reason)}")
        promote_first(rest, context, slot)
    end
  end

  defp promote(context, slot, entry) do
    with %{} = actor <- Identity.find_by_id(entry.user_id) || {:error, :not_found},
         request = request_for(slot, entry),
         {:ok, reservation} <- SubmitBooking.reserve_visit(context, actor, slot, request) do
      case Scheduling.promote_waitlisted_booking(context, entry.id) do
        {:ok, booking} ->
          SubmitBooking.broadcast_entitlement_change(entry.user_id)
          {:ok, booking}

        {:error, reason} ->
          SubmitBooking.release_failed_reservation(context, reservation)
          {:error, reason}
      end
    else
      {:error, reason, _details} -> {:error, reason}
      error -> error
    end
  end

  defp request_for(slot, entry) do
    case BookingEntitlement.allowance(entry) do
      :guest_passes -> BookingPolicy.guest_request(slot)
      _ -> BookingPolicy.entitlement_request(slot)
    end
  end

  defp notify(slot, booking) do
    Notifications.process_event("booking_waitlist_promoted", %{
      user_id: booking.user_id,
      booking_id: booking.id,
      scheduled_class_id: slot.id,
      class_name: slot.name,
      scheduled_at: slot.scheduled_at,
      status: booking.status
    })

    ScheduleRealtime.broadcast("booking_waitlist_promoted", booking)
    :ok
  rescue
    error ->
      Logger.warning("waitlist_promotion_notification_failed reason=#{Exception.message(error)}")
      :ok
  end
end
