defmodule MilosTraining.Scheduling.Domain.BookingPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Scheduling.Domain.BookingPolicy
  @now ~U[2026-07-15 12:00:00Z]

  test "slot_full?/1 returns true when bookings >= capacity" do
    slot = %{capacity: 2, approved_booking_count: 2}
    assert BookingPolicy.slot_full?(slot)
  end

  test "slot_full?/1 returns false when bookings < capacity" do
    slot = %{capacity: 10, approved_booking_count: 3}
    refute BookingPolicy.slot_full?(slot)
  end

  test "can_book?/2 returns false when slot is full" do
    slot = %{capacity: 1, approved_booking_count: 1, scheduled_at: future(), bookings: []}
    assert {:error, :slot_full} = BookingPolicy.can_book?(slot, user_id: "u1", now: @now)
  end

  test "can_book?/2 returns false when slot is in the past" do
    slot = %{capacity: 10, approved_booking_count: 0, scheduled_at: past(), bookings: []}
    assert {:error, :slot_in_past} = BookingPolicy.can_book?(slot, user_id: "u1", now: @now)
  end

  test "can_book?/2 returns false when user already has a booking" do
    slot = %{
      capacity: 10,
      approved_booking_count: 0,
      scheduled_at: future(),
      bookings: [%{user_id: "u1", status: :pending}]
    }

    assert {:error, :already_booked} = BookingPolicy.can_book?(slot, user_id: "u1", now: @now)
  end

  defp future, do: DateTime.add(@now, 3600, :second)
  defp past, do: DateTime.add(@now, -3600, :second)
end
