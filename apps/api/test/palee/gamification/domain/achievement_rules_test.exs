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
end
