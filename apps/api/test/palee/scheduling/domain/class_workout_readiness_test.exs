defmodule Palee.Scheduling.Domain.ClassWorkoutReadinessTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.ClassWorkoutReadiness, as: Readiness

  @zone "Europe/Athens"

  # 2026-11-03 18:00 in Athens (EET, UTC+2) is 16:00 UTC.
  @starts_at ~U[2026-11-03 16:00:00Z]

  defp slot(attrs \\ %{}),
    do:
      Map.merge(
        %{master_workout_id: nil, class_series_id: "series", scheduled_at: @starts_at},
        attrs
      )

  describe "published?/1" do
    test "a class with a WOD or in a series is published; a standalone one without is a draft" do
      assert Readiness.published?(slot(%{master_workout_id: "w"}))
      assert Readiness.published?(slot())
      refute Readiness.published?(slot(%{class_series_id: nil}))
      assert Readiness.ensure_published(slot(%{class_series_id: nil})) == {:error, :class_not_published}
    end

    test "a projection without the WOD field is never judged a draft" do
      assert Readiness.published?(%{scheduled_at: @starts_at})
    end
  end

  describe "workout_status/3" do
    test "a linked class is linked whatever the day" do
      assert Readiness.workout_status(slot(%{master_workout_id: "w"}), @starts_at, @zone) ==
               :linked
    end

    test "a draft is missing at once" do
      assert Readiness.workout_status(slot(%{class_series_id: nil}), ~U[2026-11-01 08:00:00Z], @zone) ==
               :missing
    end

    test "a series occurrence is awaiting until 00:00 of its own day, then missing" do
      # 23:59 Athens on the day before is 21:59 UTC.
      assert Readiness.workout_status(slot(), ~U[2026-11-02 21:59:00Z], @zone) == :awaiting
      # 00:00 Athens is 22:00 UTC the evening before.
      assert Readiness.workout_status(slot(), ~U[2026-11-02 22:00:00Z], @zone) == :missing
    end
  end

  describe "alert_moments/2 and alert_due/3" do
    test "07:00 local on the day and one hour before" do
      assert Readiness.alert_moments(slot(), @zone) == [
               {:morning, ~U[2026-11-03 05:00:00Z]},
               {:hour_before, ~U[2026-11-03 15:00:00Z]}
             ]
    end

    test "an early class only gets the hour-before alert" do
      # 07:30 Athens: the hour before (06:30) comes before 07:00.
      early = slot(%{scheduled_at: ~U[2026-11-03 05:30:00Z]})
      assert Readiness.alert_moments(early, @zone) == [{:hour_before, ~U[2026-11-03 04:30:00Z]}]
    end

    test "the latest passed moment is due while the class has not started" do
      assert Readiness.alert_due(slot(), ~U[2026-11-03 04:59:00Z], @zone) == nil
      assert {:morning, _at} = Readiness.alert_due(slot(), ~U[2026-11-03 05:02:00Z], @zone)
      assert {:hour_before, _at} = Readiness.alert_due(slot(), ~U[2026-11-03 15:20:00Z], @zone)
      assert Readiness.alert_due(slot(), @starts_at, @zone) == nil
      assert Readiness.alert_due(slot(%{master_workout_id: "w"}), ~U[2026-11-03 15:20:00Z], @zone) == nil
    end

    test "summer time shifts the UTC moment" do
      # 2026-07-07 18:00 Athens (EEST, UTC+3) is 15:00 UTC; 07:00 is 04:00 UTC.
      summer = slot(%{scheduled_at: ~U[2026-07-07 15:00:00Z]})
      assert [{:morning, ~U[2026-07-07 04:00:00Z]} | _] = Readiness.alert_moments(summer, @zone)
    end
  end
end
