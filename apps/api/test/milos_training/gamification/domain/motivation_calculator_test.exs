defmodule MilosTraining.Gamification.Domain.MotivationCalculatorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.MotivationCalculator

  describe "calculate/3" do
    test "returns 0.0 with no completed dates" do
      assert 0.0 == MotivationCalculator.calculate([], 3, ~D[2026-06-16])
    end

    test "returns 100.0 when all 10 weeks hit target" do
      # Generate 3 workouts per week for the 10 complete weeks before current_date.
      dates =
        for week <- 0..9, day <- 0..2 do
          Date.add(~D[2026-06-09], -(week * 7) + day)
        end

      result = MotivationCalculator.calculate(dates, 3, ~D[2026-06-16])
      assert result == 100.0
    end

    test "returns 50.0 when 5 of 10 weeks hit target" do
      # 5 weeks with target, 5 without
      dates =
        for week <- [1, 3, 5, 7, 9], day <- 0..2 do
          Date.add(~D[2026-06-09], -(week * 7) + day)
        end

      result = MotivationCalculator.calculate(dates, 3, ~D[2026-06-16])
      assert result == 50.0
    end

    test "returns 0.0 when no week hits target" do
      # 1 workout per week (target = 3)
      dates = for week <- 1..10, do: Date.add(~D[2026-06-09], -(week * 7))
      result = MotivationCalculator.calculate(dates, 3, ~D[2026-06-16])
      assert result == 0.0
    end
  end
end
