defmodule MilosTraining.Gamification.Domain.ChallengeRuleTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.ChallengeRule

  describe "evaluate/2 — workout_type" do
    test "awards points when workout type matches" do
      rule = %{"condition" => "workout_type", "type" => "crossfit", "points" => 3}
      assert ChallengeRule.evaluate(rule, %{workout_type: "crossfit"}) == 3
    end

    test "returns 0 when workout type does not match" do
      rule = %{"condition" => "workout_type", "type" => "crossfit", "points" => 3}
      assert ChallengeRule.evaluate(rule, %{workout_type: "strength"}) == 0
    end

    test "returns 0 when workout_type is nil" do
      rule = %{"condition" => "workout_type", "type" => "crossfit", "points" => 3}
      assert ChallengeRule.evaluate(rule, %{workout_type: nil}) == 0
    end
  end

  describe "evaluate/2 — scale_level" do
    test "awards points when scale level matches" do
      rule = %{"condition" => "scale_level", "slug" => "rx", "points" => 2}
      assert ChallengeRule.evaluate(rule, %{scale_level_slug: "rx"}) == 2
    end

    test "returns 0 when scale level does not match" do
      rule = %{"condition" => "scale_level", "slug" => "rx", "points" => 2}
      assert ChallengeRule.evaluate(rule, %{scale_level_slug: "scaled"}) == 0
    end

    test "returns 0 when scale_level_slug is nil" do
      rule = %{"condition" => "scale_level", "slug" => "rx", "points" => 2}
      assert ChallengeRule.evaluate(rule, %{scale_level_slug: nil}) == 0
    end
  end

  describe "evaluate/2 — pr_beaten" do
    test "awards points when pr_count > 0" do
      rule = %{"condition" => "pr_beaten", "points" => 5}
      assert ChallengeRule.evaluate(rule, %{pr_count: 2}) == 5
    end

    test "returns 0 when pr_count is 0" do
      rule = %{"condition" => "pr_beaten", "points" => 5}
      assert ChallengeRule.evaluate(rule, %{pr_count: 0}) == 0
    end
  end

  describe "evaluate/2 — weekly_consistency" do
    test "awards points when consistency_score meets threshold" do
      rule = %{"condition" => "weekly_consistency", "threshold" => 50, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{consistency_score: 0.6}) == 3
    end

    test "awards points when consistency_score equals threshold exactly" do
      rule = %{"condition" => "weekly_consistency", "threshold" => 50, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{consistency_score: 0.5}) == 3
    end

    test "returns 0 when below threshold" do
      rule = %{"condition" => "weekly_consistency", "threshold" => 50, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{consistency_score: 0.3}) == 0
    end
  end

  describe "evaluate/2 — rare_workout_type" do
    test "awards points when type is rarely done (below threshold)" do
      rule = %{"condition" => "rare_workout_type", "threshold_pct" => 10, "points" => 4}
      assert ChallengeRule.evaluate(rule, %{prev_type_count: 0, total_prev_completions: 9}) == 4
    end

    test "awards points on first-ever workout (0 previous completions)" do
      rule = %{"condition" => "rare_workout_type", "threshold_pct" => 10, "points" => 4}
      assert ChallengeRule.evaluate(rule, %{prev_type_count: 0, total_prev_completions: 0}) == 4
    end

    test "returns 0 when type is done more than threshold percent of the time" do
      rule = %{"condition" => "rare_workout_type", "threshold_pct" => 10, "points" => 4}
      assert ChallengeRule.evaluate(rule, %{prev_type_count: 5, total_prev_completions: 9}) == 0
    end

    test "uses default threshold_pct of 10 when absent" do
      rule = %{"condition" => "rare_workout_type", "points" => 4}
      assert ChallengeRule.evaluate(rule, %{prev_type_count: 0, total_prev_completions: 9}) == 4
    end
  end

  describe "evaluate/2 — team_workout_streak" do
    test "awards points when team workout count meets min_count" do
      rule = %{"condition" => "team_workout_streak", "min_count" => 2, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{team_workout_count: 3}) == 3
    end

    test "awards points when exactly at min_count" do
      rule = %{"condition" => "team_workout_streak", "min_count" => 2, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{team_workout_count: 2}) == 3
    end

    test "returns 0 when below min_count" do
      rule = %{"condition" => "team_workout_streak", "min_count" => 2, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{team_workout_count: 1}) == 0
    end
  end

  describe "label/1" do
    test "returns the rule's label when present" do
      rule = %{"condition" => "pr_beaten", "points" => 5, "label" => "for crushing a PR"}
      assert ChallengeRule.label(rule) == "for crushing a PR"
    end

    test "returns default label when label is absent" do
      rule = %{"condition" => "pr_beaten", "points" => 5}
      assert ChallengeRule.label(rule) == "for beating a PR"
    end
  end
end
