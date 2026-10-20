defmodule MilosTraining.Facility.Domain.ResolveScanTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Facility.Domain.{DeskAssessment, ResolveScan}

  @here "loc-here"
  @now ~U[2026-10-20 18:00:00Z]

  defp at(minutes), do: DateTime.add(@now, minutes * 60, :second)

  defp booking(id, minutes, opts \\ []) do
    %{
      id: id,
      scheduled_class_id: Keyword.get(opts, :class, "class-" <> id),
      starts_at: at(minutes),
      location_id: Keyword.get(opts, :location, @here),
      attendance: Keyword.get(opts, :attendance)
    }
  end

  defp class(id, minutes, spots, location \\ @here),
    do: %{id: id, starts_at: at(minutes), location_id: location, spots_remaining: spots}

  defp facts(overrides) do
    Map.merge(
      %{
        location_id: @here,
        member?: true,
        bookings: [],
        classes: [],
        open_gym: %{existing: nil, covered?: false}
      },
      Map.new(overrides)
    )
  end

  describe "bookings" do
    test "a booking inside the window is checked in, at both edges" do
      for minutes <- [30, 0, -15] do
        b = booking("b", minutes)
        assert {:check_in_class, ^b} = ResolveScan.decide(facts(bookings: [b]), %{}, @now)
      end
    end

    test "a booking just outside the window is not" do
      for minutes <- [31, -16] do
        assert {:nothing, _} =
                 ResolveScan.decide(facts(bookings: [booking("b", minutes)]), %{}, @now)
      end
    end

    test "owner window settings move the edges" do
      settings = %{window_before_minutes: 60, window_after_minutes: 0}

      assert {:check_in_class, _} =
               ResolveScan.decide(facts(bookings: [booking("b", 55)]), settings, @now)

      assert {:nothing, _} =
               ResolveScan.decide(facts(bookings: [booking("b", -1)]), settings, @now)
    end

    test "a booking at another location is ignored; one without a location matches" do
      assert {:nothing, _} =
               ResolveScan.decide(
                 facts(bookings: [booking("b", 5, location: "elsewhere")]),
                 %{},
                 @now
               )

      assert {:check_in_class, _} =
               ResolveScan.decide(facts(bookings: [booking("b", 5, location: nil)]), %{}, @now)
    end

    test "several bookings in the window → choose, soonest first; the pick checks in" do
      later = booking("later", 20)
      sooner = booking("sooner", -5)
      f = facts(bookings: [later, sooner])

      assert {:choose, [^sooner, ^later]} = ResolveScan.decide(f, %{}, @now)
      assert {:check_in_class, ^later} = ResolveScan.decide(f, %{}, @now, "later")
      assert {:error, :booking_not_in_window} = ResolveScan.decide(f, %{}, @now, "unknown")
    end

    test "scanning again is a no-op" do
      b = booking("b", 0, attendance: "attended")

      assert {:already_checked_in, {:class, ^b}} =
               ResolveScan.decide(facts(bookings: [b]), %{}, @now)

      assert {:already_checked_in, {:class, ^b}} =
               ResolveScan.decide(facts(bookings: [b]), %{}, @now, "b")
    end

    test "a booking marked absent by the coach cannot be picked" do
      b = booking("b", 0, attendance: "absent")

      assert {:error, :booking_not_in_window} =
               ResolveScan.decide(facts(bookings: [b]), %{}, @now, "b")
    end
  end

  describe "without a booking" do
    test "open gym when the package covers it" do
      assert :open_gym =
               ResolveScan.decide(facts(open_gym: %{existing: nil, covered?: true}), %{}, @now)
    end

    test "open gym for any member when the owner does not require a package" do
      assert :open_gym = ResolveScan.decide(facts([]), %{open_gym_requires_package: false}, @now)
    end

    test "already in open gym today is a no-op" do
      existing = %{id: "ci"}

      assert {:already_checked_in, {:open_gym, ^existing}} =
               ResolveScan.decide(
                 facts(open_gym: %{existing: existing, covered?: true}),
                 %{},
                 @now
               )
    end

    test "nothing: classes starting soon here with spots, and the next booking" do
      f =
        facts(
          bookings: [booking("next", 240, class: "c-next")],
          classes: [
            class("soon", 40, 3),
            class("full", 50, 0),
            class("elsewhere", 60, 5, "other"),
            class("too-late", 181, 5),
            class("started", -5, 5),
            class("c-next", 120, 5),
            class("anywhere", 90, 1, nil)
          ]
        )

      assert {:nothing, %{classes: classes, next_booking: %{id: "next"}}} =
               ResolveScan.decide(f, %{}, @now)

      assert Enum.map(classes, & &1.id) == ["soon", "anywhere"]
    end

    test "not a member → visitor" do
      assert :visitor = ResolveScan.decide(facts(member?: false), %{}, @now)
    end

    test "a visitor with a booking (a trial) is checked in" do
      assert {:check_in_class, _} =
               ResolveScan.decide(
                 facts(member?: false, bookings: [booking("trial", 10)]),
                 %{},
                 @now
               )
    end
  end

  describe "poster scan" do
    test "checks in a booking in the window, and picks among several" do
      b = booking("b", 10)

      assert {:check_in_class, ^b} =
               ResolveScan.decide(facts(source: :poster, bookings: [b]), %{}, @now)

      assert {:choose, [_, _]} =
               ResolveScan.decide(
                 facts(source: :poster, bookings: [b, booking("c", 20)]),
                 %{},
                 @now
               )
    end

    test "never open gym, suggestions or trials" do
      f =
        facts(
          source: :poster,
          open_gym: %{existing: nil, covered?: true},
          classes: [class("soon", 40, 3)],
          bookings: [booking("late", 60)]
        )

      assert {:poster_no_booking, :member} =
               ResolveScan.decide(f, %{open_gym_requires_package: false}, @now)

      assert {:poster_no_booking, :visitor} = ResolveScan.decide(%{f | member?: false}, %{}, @now)
    end
  end

  describe "desk assessment" do
    @active %{status: "active", frozen_until: nil}

    test "all fine with one booking → auto check-in" do
      result =
        DeskAssessment.assess(facts(bookings: [booking("b", 0)], entitlement: @active), %{}, @now)

      assert result.problems == []
      assert result.can_auto_check_in
      refute result.override_allowed
    end

    test "package problems block auto and allow override only when the owner allows it" do
      f =
        facts(bookings: [booking("b", 0)], entitlement: %{status: "inactive", frozen_until: nil})

      assert %{problems: [:package_expired], can_auto_check_in: false, override_allowed: false} =
               DeskAssessment.assess(f, %{}, @now)

      assert %{override_allowed: true} = DeskAssessment.assess(f, %{desk_override: true}, @now)
    end

    test "frozen, unpaid and grace" do
      assert %{problems: [:frozen, :nothing_to_check_in]} =
               DeskAssessment.assess(
                 facts(entitlement: %{status: "inactive", frozen_until: ~D[2026-11-01]}),
                 %{},
                 @now
               )

      assert %{problems: [:unpaid | _]} =
               DeskAssessment.assess(
                 facts(entitlement: %{status: "blocked", frozen_until: nil}),
                 %{},
                 @now
               )

      assert %{problems: [], warnings: [:payment_due], can_auto_check_in: true} =
               DeskAssessment.assess(
                 facts(
                   entitlement: %{status: "grace", frozen_until: nil},
                   open_gym: %{existing: nil, covered?: true}
                 ),
                 %{},
                 @now
               )
    end

    test "no booking: a full class now → no_spots; otherwise nothing_to_check_in" do
      assert %{problems: [:no_spots]} =
               DeskAssessment.assess(
                 facts(entitlement: @active, classes: [class("full", 5, 0)]),
                 %{},
                 @now
               )

      assert %{problems: [:nothing_to_check_in], override_allowed: true} =
               DeskAssessment.assess(facts(entitlement: @active), %{desk_override: true}, @now)
    end

    test "several bookings never auto check in" do
      result =
        DeskAssessment.assess(
          facts(entitlement: @active, bookings: [booking("a", 0), booking("b", 10)]),
          %{},
          @now
        )

      assert {:choose, _} = result.decision
      refute result.can_auto_check_in
    end

    test "override targets" do
      assert {:class, %{id: "a"}} =
               DeskAssessment.override_target({:choose, [%{id: "a"}, %{id: "b"}]})

      assert :open_gym = DeskAssessment.override_target({:nothing, %{}})
      assert nil == DeskAssessment.override_target({:already_checked_in, {:open_gym, %{}}})
    end
  end
end
