defmodule MilosTraining.Application.SubmitGuestBooking do
  @moduledoc """
  Books a named guest into a class on a member's guest passes (ADR-097). The
  guest booking counts toward capacity and follows the class's approval mode.
  """

  alias MilosTraining.Application.{BookingTerms, SubmitBooking}
  alias MilosTraining.Scheduling
  alias MilosTraining.Scheduling.Domain.BookingPolicy

  def call(context, %{id: user_id} = actor, slot_id, guest_name) do
    now = DateTime.utc_now()

    with {:ok, guest_name} <- normalize_name(guest_name),
         %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- BookingPolicy.can_book_guest?(slot, user_id, now),
         terms = BookingTerms.for_slot(context, user_id, slot),
         :ok <-
           BookingPolicy.booking_window_open?(slot.scheduled_at, now, terms.booking_window_days),
         request = BookingPolicy.guest_request(slot),
         {:ok, reservation} <- SubmitBooking.reserve_visit(context, actor, slot, request) do
      attrs = %{guest_name: guest_name, entitlement_allowance: "guest_passes"}

      case SubmitBooking.create_booking(context, slot, user_id, attrs) do
        {:ok, booking} ->
          SubmitBooking.dispatch_booking_notification(slot, booking)
          SubmitBooking.broadcast_booking_event(slot, booking)
          SubmitBooking.broadcast_entitlement_change(user_id)
          {:ok, booking}

        {:error, reason} ->
          SubmitBooking.release_failed_reservation(context, reservation)
          {:error, reason}
      end
    end
  end

  defp normalize_name(name) when is_binary(name) do
    case String.trim(name) do
      trimmed when byte_size(trimmed) >= 2 -> {:ok, String.slice(trimmed, 0, 80)}
      _ -> {:error, :invalid_guest_name}
    end
  end

  defp normalize_name(_), do: {:error, :invalid_guest_name}
end
