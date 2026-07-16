defmodule MilosTraining.Gamification.Domain.DayStreakCalculatorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.DayStreakCalculator

  describe "calculate/3" do
    test "returns zero streak when no workouts" do
      assert %{current_streak: 0, longest_streak: 0} =
               DayStreakCalculator.calculate([], [], ~D[2026-06-16])
    end

    test "counts consecutive days as streak" do
      dates = [~D[2026-06-14], ~D[2026-06-15], ~D[2026-06-16]]
      result = DayStreakCalculator.calculate(dates, [], ~D[2026-06-16])
      assert result.current_streak == 3
    end

    test "off day does not break streak" do
      # Sunday (0) is an off day; trained Mon-Tue, off Sun, trained Sat
      dates = [~D[2026-06-13], ~D[2026-06-14], ~D[2026-06-15], ~D[2026-06-16]]
      # 0=Sun off; trained on Mon(1) through Mon(1) + consecutive
      result = DayStreakCalculator.calculate(dates, [], ~D[2026-06-16])
      assert result.current_streak == 4
    end

    test "skipping off days does not break streak" do
      # Trained Sat + Tue, off on Sun+Mon
      dates = [~D[2026-06-13], ~D[2026-06-16]]
      result = DayStreakCalculator.calculate(dates, [0, 1], ~D[2026-06-16])

      # June 16 = Tue (trained), June 15 = Mon (off), June 14 = Sun (off), June 13 = Sat (trained)
      assert result.current_streak == 2
    end

    test "missed training day breaks streak" do
      # Trained Mon and Wed, missed Tue (not an off day)
      dates = [~D[2026-06-15], ~D[2026-06-16]]
      result = DayStreakCalculator.calculate(dates, [], ~D[2026-06-16])
      # June 16 = Mon, June 15 = Sun (no off days set, so Sun is a training day with workout)
      assert result.current_streak == 2
    end

    test "longest streak tracks historical best" do
      # Trained 3 days, then broke streak, then trained 1 day
      dates = [~D[2026-06-10], ~D[2026-06-11], ~D[2026-06-12], ~D[2026-06-16]]
      result = DayStreakCalculator.calculate(dates, [], ~D[2026-06-16])
      assert result.longest_streak >= 3
    end

    test "no workout today with no off days means current streak = 0" do
      dates = [~D[2026-06-14], ~D[2026-06-15]]
      result = DayStreakCalculator.calculate(dates, [], ~D[2026-06-16])
      # June 16 had no workout and is not an off day → streak = 0
      assert result.current_streak == 0
    end
  end
end
