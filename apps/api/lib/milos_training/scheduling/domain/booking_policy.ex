defmodule MilosTraining.Scheduling.Domain.BookingPolicy do
  def slot_full?(%{capacity: capacity, approved_booking_count: approved_booking_count})
      when is_integer(capacity) and is_integer(approved_booking_count) do
    approved_booking_count >= capacity
  end

  def can_book?(slot, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    now = Keyword.fetch!(opts, :now)

    cond do
      slot_full?(slot) ->
        {:error, :slot_full}

      DateTime.compare(slot.scheduled_at, now) != :gt ->
        {:error, :slot_in_past}

      already_has_booking?(slot, user_id) ->
        {:error, :already_booked}

      true ->
        :ok
    end
  end

  defp already_has_booking?(%{bookings: bookings}, user_id) when is_list(bookings) do
    Enum.any?(bookings, &(&1.user_id == user_id and &1.status in [:pending, :approved]))
  end

  defp already_has_booking?(_, _user_id), do: false
end
