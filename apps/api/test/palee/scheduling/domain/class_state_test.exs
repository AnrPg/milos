defmodule Palee.Scheduling.Domain.ClassStateTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.ClassState

  @now ~U[2026-11-01 12:00:00Z]
  @later ~U[2026-11-02 07:00:00Z]

  defp slot(attrs \\ %{}),
    do: Map.merge(%{scheduled_at: @later, paused_at: nil, cancelled_at: nil, bookings: []}, attrs)

  test "reads the five actions and refuses others" do
    assert ClassState.action("pause") == {:ok, :pause}
    assert ClassState.action(:delete) == {:ok, :delete}
    assert ClassState.action("archive") == {:error, :invalid_class_action}
    assert ClassState.action(nil) == {:error, :invalid_class_action}
  end

  test "a started class never changes" do
    for action <- [:pause, :resume, :cancel, :restore, :delete] do
      assert ClassState.plan(slot(%{scheduled_at: @now}), action, @now) == {:skip, :slot_in_past}
    end
  end

  test "pause and resume" do
    assert ClassState.plan(slot(), :pause, @now) == {:change, %{paused_at: @now}}
    assert ClassState.plan(slot(%{paused_at: @now}), :pause, @now) == {:skip, :unchanged}
    assert ClassState.plan(slot(%{cancelled_at: @now}), :pause, @now) == {:skip, :class_cancelled}

    assert ClassState.plan(slot(%{paused_at: @now}), :resume, @now) ==
             {:change, %{paused_at: nil}}

    assert ClassState.plan(slot(), :resume, @now) == {:skip, :unchanged}
  end

  test "cancel clears a pause and keeps the reason; restore undoes it" do
    assert ClassState.plan(slot(%{paused_at: @now}), :cancel, @now, "Flood") ==
             {:change, %{cancelled_at: @now, cancel_reason: "Flood", paused_at: nil}}

    assert ClassState.plan(slot(%{cancelled_at: @now}), :cancel, @now) == {:skip, :unchanged}

    assert ClassState.plan(slot(%{cancelled_at: @now}), :restore, @now) ==
             {:change, %{cancelled_at: nil, cancel_reason: nil}}
  end

  test "only a class nobody booked can be deleted" do
    assert ClassState.plan(slot(), :delete, @now) == :delete

    assert ClassState.plan(slot(%{bookings: [%{status: :rejected}]}), :delete, @now) ==
             {:skip, :class_has_bookings}
  end

  test "a cancel releases places still held, not history" do
    bookings = [
      %{id: "a", status: :approved},
      %{id: "w", status: :waitlisted},
      %{id: "p", status: :pending},
      %{id: "x", status: :attended}
    ]

    assert slot(%{bookings: bookings}) |> ClassState.released_bookings() |> Enum.map(& &1.id) ==
             ["a", "w", "p"]
  end

  test "a whole-series cancel or delete ends it; a pause doesn't" do
    assert ClassState.ends_series?(:cancel)
    assert ClassState.ends_series?(:delete)
    refute ClassState.ends_series?(:pause)
    refute ClassState.refusal?(:unchanged)
    assert ClassState.refusal?(:class_has_bookings)
  end
end
