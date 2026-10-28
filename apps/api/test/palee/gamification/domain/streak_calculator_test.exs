defmodule Palee.Gamification.Domain.StreakCalculatorTest do
  use ExUnit.Case, async: true

  alias Palee.Gamification.Domain.StreakCalculator

  test "streak increments when the current week reaches the workout target" do
    completed_dates = [~D[2026-06-01], ~D[2026-06-03], ~D[2026-06-08], ~D[2026-06-10]]

    result =
      StreakCalculator.update(%{longest_streak: 1},
        completed_dates: completed_dates,
        current_date: ~D[2026-06-10],
        target: 2
      )

    assert result.current_streak == 2
    assert result.longest_streak == 2
  end

  test "shield preserves the streak for one missed week" do
    completed_dates = [~D[2026-05-26], ~D[2026-05-28], ~D[2026-06-09], ~D[2026-06-10]]

    result =
      StreakCalculator.calculate(completed_dates,
        current_date: ~D[2026-06-10],
        target: 2,
        shield_reset_day: 1
      )

    assert result.current_streak == 2
    assert result.current_streak_shields == 0
  end

  # ADR-221: the box chooses how many shields each renewal hands out.
  test "the box's shield count decides how many missed weeks a streak survives" do
    completed_dates = [~D[2026-05-26], ~D[2026-05-28], ~D[2026-06-16], ~D[2026-06-17]]
    opts = [current_date: ~D[2026-06-17], target: 2, shield_reset_day: 1]

    two = StreakCalculator.calculate(completed_dates, Keyword.put(opts, :shields, 2))
    assert two.current_streak == 2
    assert two.current_streak_shields == 0

    one = StreakCalculator.calculate(completed_dates, Keyword.put(opts, :shields, 1))
    assert one.current_streak == 1

    none = StreakCalculator.calculate(completed_dates, Keyword.put(opts, :shields, 0))
    assert none.current_streak == 1
    assert none.current_streak_shields == 0
  end

  test "a person with no workouts starts with the box's shields" do
    assert %{current_streak_shields: 3} =
             StreakCalculator.calculate([], current_date: ~D[2026-06-17], shields: 3)
  end

  test "consistency score looks back across the last 12 weeks" do
    completed_dates = [
      ~D[2026-03-24],
      ~D[2026-04-14],
      ~D[2026-05-12],
      ~D[2026-06-09],
      ~D[2026-06-10]
    ]

    result =
      StreakCalculator.calculate(completed_dates,
        current_date: ~D[2026-06-10],
        target: 2
      )

    assert result.consistency_score > 0.0
    assert result.consistency_score < 100.0
  end

  test "streak decays when trailing weeks are missed after the last completion" do
    completed_dates = [~D[2026-05-26], ~D[2026-05-28], ~D[2026-06-02], ~D[2026-06-03]]

    result =
      StreakCalculator.calculate(completed_dates,
        current_date: ~D[2026-06-24],
        target: 2,
        shield_reset_day: 1
      )

    assert result.current_streak == 0
  end
end
