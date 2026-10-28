defmodule Palee.Scheduling.Domain.BookingPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.BookingPolicy
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

  describe "approval_deadline/3 (ADR-222)" do
    test "a limited request waits that long from now" do
      starts_at = DateTime.add(@now, 3 * 3600, :second)

      assert BookingPolicy.approval_deadline(@now, 90, starts_at) ==
               DateTime.add(@now, 90 * 60, :second)
    end

    test "a request never waits past the class start" do
      starts_at = DateTime.add(@now, 30 * 60, :second)
      assert BookingPolicy.approval_deadline(@now, 90, starts_at) == starts_at
    end

    test "no limit waits until the class starts" do
      starts_at = DateTime.add(@now, 2 * 86_400, :second)
      assert BookingPolicy.approval_deadline(@now, nil, starts_at) == starts_at
    end
  end

  describe "late_cancellation?/4 counts the cutoff in minutes (ADR-222)" do
    test "inside the cutoff is late" do
      starts_at = DateTime.add(@now, 89 * 60, :second)
      assert BookingPolicy.late_cancellation?(:approved, starts_at, @now, 90)
    end

    test "outside the cutoff is free" do
      starts_at = DateTime.add(@now, 91 * 60, :second)
      refute BookingPolicy.late_cancellation?(:approved, starts_at, @now, 90)
    end

    test "no cutoff or a request that was never approved is never late" do
      starts_at = DateTime.add(@now, 60, :second)
      refute BookingPolicy.late_cancellation?(:approved, starts_at, @now, nil)
      refute BookingPolicy.late_cancellation?(:pending, starts_at, @now, 90)
    end
  end

  defp future, do: DateTime.add(@now, 3600, :second)
  defp past, do: DateTime.add(@now, -3600, :second)
end
