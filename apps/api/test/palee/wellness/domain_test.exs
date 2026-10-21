defmodule Palee.Wellness.DomainTest do
  use ExUnit.Case, async: true

  alias Palee.Wellness.Domain.{CravingPolicy, DaySummary, EntryKinds, LocalDay, Sleep}
  alias Palee.Wellness.Preferences

  describe "values" do
    test "water is millilitres, required, at most 3 L a drink" do
      assert {:ok, %{"ml" => 250}} = EntryKinds.cast("water", %{"ml" => 250})
      assert {:ok, %{"ml" => 500}} = EntryKinds.cast("water", %{ml: 500})
      assert {:error, {:invalid_wellness_value, %{"ml" => _}}} = EntryKinds.cast("water", %{})
      assert {:error, {:invalid_wellness_value, _}} = EntryKinds.cast("water", %{"ml" => 0})
      assert {:error, {:invalid_wellness_value, _}} = EntryKinds.cast("water", %{"ml" => 3_001})
    end

    test "sleep from bedtime and wake time works out the minutes and counts on waking" do
      assert {:ok, value} =
               EntryKinds.cast("sleep", %{
                 "bed_at" => "2026-10-19T23:40:00+03:00",
                 "wake_at" => "2026-10-20T06:50:00+03:00",
                 "quality" => 4
               })

      assert %{"minutes" => 430, "quality" => 4, "nap" => false} = value
      assert value["wake_at"] == "2026-10-20T03:50:00Z"
      assert Sleep.counts_at(value, ~U[2026-10-20 09:00:00Z]) == ~U[2026-10-20 03:50:00Z]
    end

    test "sleep needs hours or a quality, and both ends when one is given" do
      assert {:ok, %{"minutes" => 420}} = EntryKinds.cast("sleep", %{"minutes" => 420})
      assert {:ok, %{"quality" => 3}} = EntryKinds.cast("sleep", %{"quality" => 3})

      assert {:error, {:invalid_wellness_value, %{"minutes" => _}}} =
               EntryKinds.cast("sleep", %{})

      assert {:error, {:invalid_wellness_value, %{"wake_at" => _}}} =
               EntryKinds.cast("sleep", %{"bed_at" => "2026-10-19T23:00:00Z", "quality" => 3})

      assert {:error, {:invalid_wellness_value, %{"wake_at" => _}}} =
               EntryKinds.cast("sleep", %{
                 "bed_at" => "2026-10-20T07:00:00Z",
                 "wake_at" => "2026-10-20T06:00:00Z"
               })

      assert {:error, {:invalid_wellness_value, %{"quality" => _}}} =
               EntryKinds.cast("sleep", %{"quality" => 6})
    end

    test "a meal takes a slot, in or out of plan, a note and hand portions in halves" do
      assert {:ok, value} =
               EntryKinds.cast("meal", %{
                 "slot" => "lunch",
                 "plan_fit" => "off_plan",
                 "note" => "  σουβλάκι  ",
                 "portions" => %{"protein" => 2, "carbs" => 1.5}
               })

      assert value == %{
               "slot" => "lunch",
               "plan_fit" => "off_plan",
               "note" => "σουβλάκι",
               "portions" => %{"protein" => 2, "carbs" => 1.5}
             }

      assert {:ok, %{}} = EntryKinds.cast("meal", %{})

      for bad <- [
            %{"slot" => "brunch"},
            %{"plan_fit" => "cheat"},
            %{"portions" => %{"protein" => 1.3}},
            %{"portions" => %{"calories" => 1}},
            %{"media_id" => "nope"}
          ] do
        assert {:error, {:invalid_wellness_value, _}} = EntryKinds.cast("meal", bad)
      end
    end

    test "unknown kinds are refused" do
      assert {:error, :unknown_wellness_kind} = EntryKinds.cast("steps", %{})
    end
  end

  test "the local day follows the member's zone" do
    assert {:ok, ~D[2026-10-21]} = LocalDay.of(~U[2026-10-20 22:30:00Z], "Europe/Athens")
    assert {:ok, ~D[2026-10-20]} = LocalDay.of(~U[2026-10-20 22:30:00Z], "Etc/UTC")
    assert {:error, :unknown_time_zone} = LocalDay.of(~U[2026-10-20 22:30:00Z], "Mars/Base")

    assert {:ok, ~D[2026-10-14], ~D[2026-10-20]} =
             LocalDay.parse_window("2026-10-14", "2026-10-20")

    assert {:error, :invalid_date} = LocalDay.parse_window("2026-10-20", "2026-10-14")
    assert {:error, :date_window_too_long} = LocalDay.parse_window("2026-01-01", "2026-10-20")
  end

  test "an ongoing craving is followed up once, 20 minutes later; causes keep catalogue order" do
    now = ~U[2026-10-20 18:00:00Z]
    assert CravingPolicy.follow_up_at(nil, now) == ~U[2026-10-20 18:20:00Z]
    assert CravingPolicy.follow_up_at("ongoing", now) == ~U[2026-10-20 18:20:00Z]
    assert CravingPolicy.follow_up_at("resisted", now) == nil

    assert {:ok, ["stress", "hunger"]} =
             CravingPolicy.normalize_triggers(["hunger", "stress", "stress"])

    assert {:error, :invalid_craving_trigger} = CravingPolicy.normalize_triggers(["sadness"])
  end

  describe "day summary" do
    @prefs %Preferences{water_goal_ml: 2_000, glass_ml: 250, sleep_goal_minutes: 420}

    defp entry(kind, on, value, source \\ "manual"),
      do: %{id: Ecto.UUID.generate(), kind: kind, occurred_on: on, value: value, source: source}

    test "measures each item against the member's own targets only" do
      d1 = ~D[2026-10-19]
      d2 = ~D[2026-10-20]

      entries =
        List.duplicate(entry("water", d1, %{"ml" => 500}), 4) ++
          [
            entry("water", d2, %{"ml" => 250}),
            entry("sleep", d1, %{"minutes" => 450, "quality" => 4, "nap" => false}, "garmin"),
            entry("sleep", d1, %{"minutes" => 30, "nap" => true}),
            entry("sleep", d2, %{"minutes" => 360, "nap" => false}),
            entry("meal", d1, %{"slot" => "breakfast"}),
            entry("meal", d1, %{"slot" => "lunch", "plan_fit" => "off_plan"}),
            entry("meal", d1, %{"slot" => "dinner"}),
            entry("meal", d2, %{"slot" => "breakfast"})
          ]

      cravings = [%{occurred_on: d2}]
      moods = %{d2 => %{mood: 3, stress: 2}}

      [day1, day2] = DaySummary.build([d1, d2], entries, cravings, moods, @prefs)

      assert %{ml: 2_000, count: 4, status: "full"} = day1.water

      assert %{minutes: 450, quality: 4, source: "garmin", nap_minutes: 30, status: "full"} =
               day1.sleep

      assert %{count: 3, status: "full"} = day1.meals
      assert %{count: 0, status: "none"} = day1.cravings
      assert day1.mood == nil

      assert %{ml: 250, status: "partial"} = day2.water
      assert %{minutes: 360, status: "partial"} = day2.sleep
      assert %{count: 1, status: "partial"} = day2.meals
      assert %{count: 1, status: "logged"} = day2.cravings
      assert day2.mood == %{mood: 3, stress: 2}

      assert DaySummary.week_line([day1, day2]) == %{
               nights_logged: 2,
               nights_on_goal: 1,
               water_days_logged: 2,
               water_days_on_goal: 1,
               meal_days_logged: 2,
               cravings: 1
             }
    end

    test "an empty day is all none" do
      [day] = DaySummary.build([~D[2026-10-20]], [], [], %{}, @prefs)

      assert day.water.status == "none" and day.sleep.status == "none" and
               day.meals.status == "none"

      assert day.sleep.minutes == nil
    end
  end
end
