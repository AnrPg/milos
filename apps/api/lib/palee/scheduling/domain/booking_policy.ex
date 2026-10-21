defmodule Palee.Scheduling.Domain.BookingPolicy do
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
    Enum.any?(
      bookings,
      &(&1.user_id == user_id and &1.status in [:pending, :approved, :waitlisted] and
          is_nil(Map.get(&1, :guest_name)))
    )
  end

  defp already_has_booking?(_, _user_id), do: false

  # ── Phase B rules (ADR-097) ────────────────────────────────────────────

  @doc "Package value wins over the gym default; nil means no rule."
  def effective_rule(package_value, _gym_default) when is_integer(package_value),
    do: package_value

  def effective_rule(_package_value, gym_default), do: gym_default

  @doc "A class can be booked once it is within the booking window."
  def booking_window_open?(_scheduled_at, _now, nil), do: :ok

  def booking_window_open?(%DateTime{} = scheduled_at, %DateTime{} = now, days)
      when is_integer(days) do
    opens_at = DateTime.add(scheduled_at, -days * 86_400, :second)

    if DateTime.compare(now, opens_at) == :lt,
      do: {:error, :booking_window_closed, %{opens_at: opens_at}},
      else: :ok
  end

  @doc "Withdrawing an approved booking inside the cutoff is a late cancellation."
  def late_cancellation?(_status, _scheduled_at, _now, nil), do: false

  def late_cancellation?(:approved, %DateTime{} = scheduled_at, %DateTime{} = now, hours)
      when is_integer(hours) do
    DateTime.compare(now, DateTime.add(scheduled_at, -hours * 3600, :second)) != :lt
  end

  def late_cancellation?(_status, _scheduled_at, _now, _hours), do: false

  @doc "A full, future class accepts waitlist entries."
  def can_join_waitlist?(slot, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    now = Keyword.fetch!(opts, :now)

    cond do
      DateTime.compare(slot.scheduled_at, now) != :gt -> {:error, :slot_in_past}
      not slot_full?(slot) -> {:error, :slot_not_full}
      already_has_booking?(slot, user_id) -> {:error, :already_booked}
      true -> :ok
    end
  end

  @doc """
  Guests need a free spot in a future class. A member brings at most one guest
  per class: guest passes are reserved per class in the ledger.
  """
  def can_book_guest?(slot, user_id, now) do
    cond do
      DateTime.compare(slot.scheduled_at, now) != :gt -> {:error, :slot_in_past}
      has_guest?(slot, user_id) -> {:error, :guest_already_booked}
      slot_full?(slot) -> {:error, :slot_full}
      true -> :ok
    end
  end

  defp has_guest?(%{bookings: bookings}, user_id) when is_list(bookings) do
    Enum.any?(bookings, fn booking ->
      booking.user_id == user_id and Map.get(booking, :guest_name) not in [nil, ""] and
        booking.status in [:pending, :approved, :waitlisted]
    end)
  end

  defp has_guest?(_slot, _user_id), do: false

  @doc "Waitlist order: higher priority first, then earliest join."
  def waitlist_order(entries) do
    Enum.sort_by(entries, fn entry ->
      {-(entry.waitlist_priority || 0), DateTime.to_unix(entry.waitlisted_at, :microsecond)}
    end)
  end

  def waitlist_priority("high"), do: 1
  def waitlist_priority(_), do: 0

  @doc "Ledger request for booking a class or an event (ADR-097)."
  def entitlement_request(%{class_type: %{kind: "event"}} = slot) do
    %{
      channel: :events,
      capability: :book_events,
      allowance: :event_visits,
      quantity: credit_cost(slot)
    }
  end

  def entitlement_request(slot) do
    %{
      channel: :in_person,
      capability: :book_classes,
      allowance: :class_visits,
      class_type_id: Map.get(slot, :class_type_id),
      quantity: credit_cost(slot)
    }
  end

  def guest_request(slot) do
    %{
      channel: :in_person,
      capability: :bring_guests,
      allowance: :guest_passes,
      quantity: 1,
      class_type_id: Map.get(slot, :class_type_id)
    }
  end

  def booking_allowance(%{allowance: allowance}), do: Atom.to_string(allowance)

  defp credit_cost(%{class_type: %{credit_cost: cost}}) when is_integer(cost) and cost > 0,
    do: cost

  defp credit_cost(_slot), do: 1
end
