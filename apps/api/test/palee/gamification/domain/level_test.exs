defmodule Palee.Gamification.Domain.LevelTest do
  use ExUnit.Case, async: true

  alias Palee.Gamification.Domain.Level

  describe "xp/1 (ADR-285)" do
    test "adds up every fact at its points" do
      stats = %{
        total_workouts: 4,
        total_prs: 1,
        advancement_count: 2,
        weeks_on_goal: 3,
        challenges_completed: 1
      }

      # 4 × 50 + 3 × 100 + 3 × 150 + 1 × 300
      assert Level.xp(stats) == 1_250
    end

    test "missing, nil or negative facts count as nothing" do
      assert Level.xp(%{}) == 0
      assert Level.xp(%{total_workouts: nil, weeks_on_goal: -2}) == 0
    end
  end

  describe "present/1" do
    test "a new person is level 1 with 200 XP to go" do
      assert %{level: 1, xp: 0, level_start_xp: 0, next_level_xp: 200} = Level.present(nil)
    end

    test "each level takes 100 XP more than the one before" do
      assert Level.step(1) == 200
      assert Level.step(2) == 300
      assert Level.step(7) == 800

      # Level 3 starts at 200 + 300 = 500 and ends at 500 + 400 = 900.
      assert %{level: 3, level_start_xp: 500, next_level_xp: 900} =
               Level.present(%{total_workouts: 12})
    end

    test "reaching the threshold exactly moves up a level" do
      assert %{level: 2, level_start_xp: 200} = Level.present(%{total_workouts: 4})
      assert %{level: 1} = Level.present(%{total_workouts: 3})
    end

    test "lists the points per fact for the explainer" do
      assert Level.present(%{}).points == %{
               workouts: 50,
               prs: 100,
               weeks_on_goal: 150,
               challenges: 300
             }
    end
  end
end
