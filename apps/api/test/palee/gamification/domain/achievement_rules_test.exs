defmodule Palee.Gamification.Domain.AchievementRulesTest do
  use ExUnit.Case, async: true

  alias Palee.Gamification.Domain.AchievementRules

  @stats %{total_workouts: 0, total_prs: 0, current_streak: 0}

  describe "ADR-275: mastery badges count a workout family" do
    test "kinds of one family add up" do
      badges = AchievementRules.milestone_badges(@stats, %{"boxing" => 4, "muay_thai" => 6})
      assert "type_combat_mastery" in badges
    end

    test "the original kinds keep their badges" do
      assert "type_crossfit_mastery" in AchievementRules.milestone_badges(@stats, %{
               "crossfit" => 10
             })

      assert "type_aerobics_mastery" in AchievementRules.milestone_badges(@stats, %{
               "running" => 10
             })

      assert "type_flexibility_mastery" in AchievementRules.milestone_badges(@stats, %{
               "flexibility" => 5,
               "yoga" => 5
             })
    end

    test "fewer than ten in a family, or unknown kinds, earn nothing" do
      assert AchievementRules.milestone_badges(@stats, %{"dance" => 9, "karaoke" => 50}) == []
    end

    test "badge labels" do
      assert AchievementRules.badge_label("type_dance_mastery") == "Dancer"
    end
  end

  describe "next_milestone/2 (ADR-285)" do
    test "the badge with the largest share done comes first" do
      stats = %{total_workouts: 45, total_prs: 3, current_streak: 2}

      assert %{badge_key: "workouts_50", kind: "workouts", current: 45, target: 50, remaining: 5} =
               AchievementRules.next_milestone(stats, ["workouts_25"])
    end

    test "a tie goes to the fewest steps left" do
      # prs 2/5 = workouts 4/10 = 40%: the PR badge needs 3, the workout one 6.
      assert %{badge_key: "prs_5"} =
               AchievementRules.next_milestone(%{total_workouts: 4, total_prs: 2}, [])
    end

    test "an earned streak badge is skipped even after the streak fell" do
      stats = %{total_workouts: 1, current_streak: 6}

      assert %{badge_key: "streak_7"} = AchievementRules.next_milestone(stats, ["workouts_1"])

      assert %{badge_key: "workouts_10"} =
               AchievementRules.next_milestone(stats, ["workouts_1", "streak_7", "streak_30"])
    end

    test "nil when every ladder is complete" do
      stats = %{total_workouts: 400, total_prs: 60, current_streak: 100}
      assert AchievementRules.next_milestone(stats, []) == nil
    end

    test "a new person starts at the first workout" do
      assert %{badge_key: "workouts_1", remaining: 1} = AchievementRules.next_milestone(nil, [])
    end
  end
end
