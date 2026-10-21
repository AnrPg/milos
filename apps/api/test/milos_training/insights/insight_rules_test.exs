defmodule MilosTraining.Insights.InsightRulesTest do
  @moduledoc "ADR-166: the pure insight rules, the sufficiency gate and the slot view."

  use ExUnit.Case, async: true

  alias MilosTraining.Insights.Domain.{InsightCatalog, Sufficiency}

  alias MilosTraining.Insights.Domain.Rules.{
    CravingsPattern,
    Hydration,
    SleepEffort,
    SleepPRs,
    TimeOfDay
  }

  @today ~D[2026-10-21]

  defp day(offset), do: Date.add(@today, -offset)

  defp at(offset, hour),
    do: DateTime.new!(day(offset), Time.new!(hour, 0, 0), "Etc/UTC")

  defp session(offset, opts \\ []),
    do: %{at: at(offset, Keyword.get(opts, :hour, 18)), tz: "Etc/UTC", rpe: opts[:rpe]}

  defp summary(offset, opts) do
    %{
      date: day(offset),
      sleep: %{minutes: opts[:sleep]},
      water: %{ml: opts[:water] || 0, status: if(opts[:on_goal], do: "full", else: "partial")}
    }
  end

  defp inputs(attrs) do
    Map.merge(
      %{
        today: @today,
        from: InsightCatalog.window_start(@today),
        sessions: [],
        pr_days: [],
        days: [],
        cravings: [],
        sleep_goal_minutes: 420
      },
      Map.new(attrs)
    )
  end

  describe "sufficiency" do
    test "four weeks of data, at most twelve counted" do
      refute Sufficiency.enough_span?([day(26)], @today)
      assert Sufficiency.enough_span?([day(27)], @today)
      assert Sufficiency.weeks([day(27)], @today) == 4
      assert Sufficiency.weeks([day(200)], @today) == 12
      assert Sufficiency.weeks([], @today) == 0
    end

    test "places an instant in the member's zone and part of day" do
      utc = DateTime.new!(~D[2026-10-20], ~T[22:30:00], "Etc/UTC")
      assert Sufficiency.local(utc, "Europe/Athens") == {~D[2026-10-21], 1}
      assert Sufficiency.local(utc, "Not/AZone") == {~D[2026-10-20], 22}

      assert Enum.map([6, 13, 18, 23, 3], &Sufficiency.part/1) ==
               ~w(morning afternoon evening night night)
    end
  end

  describe "sleep ↔ PRs" do
    # Ten training days over five weeks: five after 8 h, five after 6 h.
    defp sleep_days(rested_prs, short_prs) do
      rested = [1, 5, 9, 13, 30]
      short = [3, 7, 11, 15, 32]

      %{
        sessions: Enum.map(rested ++ short, &session/1),
        days:
          Enum.map(rested, &summary(&1, sleep: 480)) ++ Enum.map(short, &summary(&1, sleep: 360)),
        pr_days: Enum.map(Enum.take(rested, rested_prs) ++ Enum.take(short, short_prs), &day/1)
      }
    end

    test "more often after reaching the sleep goal" do
      result = SleepPRs.compute(inputs(sleep_days(4, 1)))
      assert result.status == :finding
      assert result.variant == "more_after_goal"
      assert result.params == %{"hours" => 7.0, "ratio" => 4.0}
      assert result.weeks == 4
    end

    test "only after reaching the goal" do
      result = SleepPRs.compute(inputs(sleep_days(3, 0)))
      assert {result.variant, result.params["pr_days"]} == {"all_after_goal", 3}
    end

    test "no clear difference is no finding" do
      assert SleepPRs.compute(inputs(sleep_days(2, 2))).status == :no_finding
    end

    test "too few PRs or days is insufficient" do
      assert SleepPRs.compute(inputs(sleep_days(1, 1))).status == :insufficient

      few = sleep_days(4, 1) |> Map.update!(:sessions, &Enum.drop(&1, 1))
      assert SleepPRs.compute(inputs(few)).status == :insufficient
    end

    test "under four weeks is insufficient" do
      recent = %{
        sessions: Enum.map(1..10, &session/1),
        days: Enum.map(1..10, &summary(&1, sleep: if(rem(&1, 2) == 0, do: 480, else: 360))),
        pr_days: Enum.map([2, 4, 6], &day/1)
      }

      result = SleepPRs.compute(inputs(recent))
      assert {result.status, result.weeks} == {:insufficient, 1}
    end
  end

  describe "sleep ↔ perceived effort" do
    test "sessions after a short night rated harder" do
      rested = [1, 5, 9, 13, 30]
      short = [3, 7, 11, 15, 32]

      data = %{
        sessions: Enum.map(rested, &session(&1, rpe: 6)) ++ Enum.map(short, &session(&1, rpe: 8)),
        days:
          Enum.map(rested, &summary(&1, sleep: 450)) ++ Enum.map(short, &summary(&1, sleep: 300))
      }

      result = SleepEffort.compute(inputs(data))

      assert {result.variant, result.params} ==
               {"harder_after_short", %{"hours" => 7.0, "delta" => 2.0}}

      same = %{data | sessions: Enum.map(rested ++ short, &session(&1, rpe: 7))}
      assert SleepEffort.compute(inputs(same)).status == :no_finding

      unrated = %{data | sessions: Enum.map(rested ++ short, &session/1)}
      assert SleepEffort.compute(inputs(unrated)).status == :insufficient
    end
  end

  describe "time of day" do
    test "the part of the day with PRs more often" do
      mornings = [1, 3, 5, 7, 9, 30]
      evenings = [2, 4, 6, 8, 10, 31]

      data = %{
        sessions:
          Enum.map(mornings, &session(&1, hour: 7)) ++ Enum.map(evenings, &session(&1, hour: 19)),
        pr_days: Enum.map([1, 3, 5, 7, 2], &day/1)
      }

      result = TimeOfDay.compute(inputs(data))

      assert {result.variant, result.params} ==
               {"best_part", %{"part" => "morning", "ratio" => 4.0}}

      assert result.key == "best_part:morning"

      only = %{data | pr_days: Enum.map([1, 3, 5, 7], &day/1)}
      assert TimeOfDay.compute(inputs(only)).variant == "only_part"

      even = %{data | pr_days: Enum.map([1, 3, 2, 4], &day/1)}
      assert TimeOfDay.compute(inputs(even)).status == :no_finding
    end

    test "one part only is insufficient" do
      data = %{sessions: Enum.map(1..30, &session(&1, hour: 7)), pr_days: Enum.map(1..6, &day/1)}
      assert TimeOfDay.compute(inputs(data)).status == :insufficient
    end
  end

  describe "cravings" do
    defp craving(offset, hour, triggers),
      do: %{occurred_at: at(offset, hour), occurred_tz: "Etc/UTC", triggers: triggers}

    test "mostly in one part of the day, mostly with one cause" do
      cravings =
        Enum.map([1, 3, 5, 7, 9, 30], &craving(&1, 22, ["stress"])) ++
          [craving(2, 15, ["boredom"]), craving(4, 9, [])]

      result = CravingsPattern.compute(inputs(cravings: cravings))
      assert result.variant == "part_and_trigger"

      assert Map.take(result.params, ~w(part part_count trigger trigger_count total)) == %{
               "part" => "night",
               "part_count" => 6,
               "trigger" => "stress",
               "trigger_count" => 6,
               "total" => 8
             }

      assert result.key == "part_and_trigger:night:stress"
    end

    test "spread out is no finding; few is insufficient; «other» is never named" do
      spread =
        Enum.map(Enum.with_index([1, 3, 5, 7, 9, 11, 13, 30]), fn {offset, index} ->
          craving(offset, Enum.at([7, 13, 18, 23], rem(index, 4)), ["other"])
        end)

      assert CravingsPattern.compute(inputs(cravings: spread)).status == :no_finding

      assert CravingsPattern.compute(inputs(cravings: Enum.take(spread, 7))).status ==
               :insufficient
    end
  end

  describe "hydration" do
    test "days on the member's own goal, and training days against rest days" do
      days =
        Enum.map(0..13, &summary(&1 * 2, water: 2000, on_goal: true)) ++
          Enum.map(0..13, &summary(&1 * 2 + 1, water: 750))

      sessions = Enum.map(0..13, &session(&1 * 2))
      result = Hydration.compute(inputs(days: days, sessions: sessions))
      assert result.variant == "training_more"

      assert result.params == %{
               "logged_days" => 28,
               "on_goal_days" => 14,
               "percent" => 50,
               "training_percent" => 100,
               "rest_percent" => 0
             }

      assert Hydration.compute(inputs(days: days)).variant == "on_goal"
      assert Hydration.compute(inputs(days: Enum.take(days, 13))).status == :insufficient
    end
  end

  describe "catalog" do
    defp row(rule, status, attrs \\ %{}) do
      Map.merge(
        %{
          rule: rule,
          status: status,
          value: %{"weeks" => 5},
          fingerprint: if(status == "finding", do: "#{rule}:x"),
          dismissed_fingerprint: nil,
          computed_at: ~U[2026-10-21 01:00:00Z]
        },
        attrs
      )
    end

    @on %{sections: %{"wellness" => true, "cravings" => true}, hidden_items: []}

    test "a switched-off section or hidden item produces nothing" do
      off = %{sections: %{"wellness" => false, "cravings" => true}, hidden_items: []}
      results = InsightCatalog.evaluate(inputs([]), off)
      statuses = Map.new(results, &{&1.rule, &1.status})

      assert statuses == %{
               "sleep_prs" => "off",
               "sleep_effort" => "off",
               "time_of_day" => "insufficient",
               "cravings" => "insufficient",
               "hydration" => "off"
             }

      hidden = InsightCatalog.evaluate(inputs([]), %{@on | hidden_items: ["water"]})
      assert Enum.find(hidden, &(&1.rule == "hydration")).status == "off"
      assert Enum.find(hidden, &(&1.rule == "sleep_prs")).status == "insufficient"
    end

    test "at most three findings in the fixed order; dismissed ones make room" do
      rows = Enum.map(InsightCatalog.rule_ids(), &row(&1, "finding"))
      view = InsightCatalog.view(rows, @on)
      assert view.state == "insights"
      assert Enum.map(view.insights, & &1.rule) == ~w(sleep_prs sleep_effort time_of_day)

      dismissed =
        Enum.map(rows, fn
          %{rule: "sleep_effort"} = row -> %{row | dismissed_fingerprint: row.fingerprint}
          row -> row
        end)

      view = InsightCatalog.view(dismissed, @on)
      assert Enum.map(view.insights, & &1.rule) == ~w(sleep_prs time_of_day cravings)
      assert view.hidden_count == 1

      changed =
        Enum.map(dismissed, fn
          %{rule: "sleep_effort"} = row -> %{row | fingerprint: "sleep_effort:y"}
          row -> row
        end)

      assert InsightCatalog.view(changed, @on).hidden_count == 0

      off = %{@on | sections: %{"wellness" => false, "cravings" => true}}

      assert Enum.map(InsightCatalog.view(rows, off).insights, & &1.rule) ==
               ~w(time_of_day cravings)
    end

    test "slot states and freshness" do
      collecting = Enum.map(InsightCatalog.rule_ids(), &row(&1, "insufficient"))
      assert InsightCatalog.view(collecting, @on).state == "collecting"
      assert InsightCatalog.view(collecting, @on).data_weeks == 5
      assert InsightCatalog.view([], @on).state == "collecting"

      pattern =
        Enum.reject(collecting, &(&1.rule == "time_of_day")) ++ [row("time_of_day", "no_finding")]

      assert InsightCatalog.view(pattern, @on).state == "no_pattern"

      hidden = [row("time_of_day", "finding", %{dismissed_fingerprint: "time_of_day:x"})]
      assert InsightCatalog.view(hidden, @on).state == "all_hidden"

      now = ~U[2026-10-21 12:00:00Z]
      assert InsightCatalog.current?(collecting, @on, now)
      refute InsightCatalog.current?(tl(collecting), @on, now)
      refute InsightCatalog.current?(collecting, @on, ~U[2026-10-22 02:00:00Z])

      off = %{@on | sections: %{"wellness" => false, "cravings" => true}}
      refute InsightCatalog.current?(collecting, off, now)
    end
  end
end
