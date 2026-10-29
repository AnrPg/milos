defmodule Palee.Scheduling.Domain.DayWorkoutInheritanceTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.DayWorkoutInheritance, as: Inheritance

  @now ~U[2026-11-03 08:00:00Z]
  @later ~U[2026-11-03 16:00:00Z]

  defp class(attrs \\ %{}) do
    Map.merge(
      %{
        id: "c1",
        scheduled_at: @later,
        class_type_id: "crossfit",
        class_kind: "class",
        location_id: "north",
        class_series_id: nil,
        master_workout_id: nil,
        day_workout_id: nil,
        booked: false
      },
      attrs
    )
  end

  defp rule(id, attrs \\ %{}) do
    Map.merge(
      %{id: id, class_type_id: nil, location_id: nil, master_workout_id: "w-#{id}"},
      attrs
    )
  end

  describe "winner/2" do
    test "the most specific covering rule wins: type over branch over all" do
      all = rule("all")
      branch = rule("branch", %{location_id: "north"})
      type = rule("type", %{class_type_id: "crossfit"})
      both = rule("both", %{class_type_id: "crossfit", location_id: "north"})

      assert Inheritance.winner([all], class()) == all
      assert Inheritance.winner([all, branch], class()) == branch
      assert Inheritance.winner([branch, type, all], class()) == type
      assert Inheritance.winner([all, type, both, branch], class()) == both
    end

    test "rules for another type or branch do not cover the class" do
      assert Inheritance.winner([rule("t", %{class_type_id: "yoga"})], class()) == nil
      assert Inheritance.winner([rule("b", %{location_id: "south"})], class()) == nil
    end

    test "an all-types rule skips events; a rule naming the event's type covers it" do
      event = class(%{class_kind: "event", class_type_id: "seminar"})

      assert Inheritance.winner([rule("all")], event) == nil

      assert %{id: "named"} =
               Inheritance.winner([rule("named", %{class_type_id: "seminar"})], event)
    end
  end

  describe "change/4" do
    test "a class without a WOD inherits the winning rule" do
      assert {:inherit, %{id: "all"}} = Inheritance.change(class(), [rule("all")], @now)
    end

    test "an inherited class follows a replaced WOD and keeps an unchanged one" do
      inherited = class(%{day_workout_id: "all", master_workout_id: "old"})

      assert {:inherit, %{master_workout_id: "w-all"}} =
               Inheritance.change(inherited, [rule("all")], @now)

      same = class(%{day_workout_id: "all", master_workout_id: "w-all"})
      assert Inheritance.change(same, [rule("all")], @now) == :keep
    end

    test "a class's own WOD beats the day's unless replace_own names that rule" do
      own = class(%{master_workout_id: "mine"})
      rules = [rule("all")]

      assert Inheritance.change(own, rules, @now) == :keep
      assert {:inherit, _} = Inheritance.change(own, rules, @now, replace_own: true)

      assert Inheritance.change(own, rules, @now, replace_own: true, only_rule_ids: ["other"]) ==
               :keep
    end

    test "a started class never changes" do
      started = class(%{scheduled_at: ~U[2026-11-03 07:00:00Z]})
      assert Inheritance.change(started, [rule("all")], @now) == :keep
    end

    test "an inherited WOD no rule covers is cleared, or kept as its own when booked and standalone" do
      inherited = class(%{day_workout_id: "gone", master_workout_id: "w"})
      assert Inheritance.change(inherited, [], @now) == :clear
      assert Inheritance.change(%{inherited | booked: true}, [], @now) == :detach

      in_series = %{inherited | booked: true, class_series_id: "s"}
      assert Inheritance.change(in_series, [], @now) == :clear
    end

    test "a class with no WOD and no covering rule is left alone" do
      assert Inheritance.change(class(), [], @now) == :keep
    end
  end

  describe "source/1" do
    test "day for inherited, class for its own, nil without a WOD" do
      assert Inheritance.source(class(%{master_workout_id: "w", day_workout_id: "r"})) == "day"
      assert Inheritance.source(class(%{master_workout_id: "w"})) == "class"
      assert Inheritance.source(class()) == nil
    end
  end

  describe "preview/4 and with_candidates/2" do
    test "splits the classes the candidate wins into inherit, own and started" do
      candidate = rule(:candidate)
      type_rule = rule("type", %{class_type_id: "yoga"})
      rules = Inheritance.with_candidates([rule("old"), type_rule], [candidate])

      refute Enum.any?(rules, &(&1.id == "old"))

      classes = [
        class(%{id: "free"}),
        class(%{id: "own", master_workout_id: "mine"}),
        class(%{id: "started", scheduled_at: ~U[2026-11-03 07:00:00Z]}),
        class(%{id: "yoga", class_type_id: "yoga"})
      ]

      preview = Inheritance.preview(classes, rules, @now, [:candidate])

      assert Enum.map(preview.inherit, & &1.id) == ["free"]
      assert Enum.map(preview.own, & &1.id) == ["own"]
      assert Enum.map(preview.started, & &1.id) == ["started"]
    end
  end
end
