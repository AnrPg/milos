defmodule MilosTraining.Gamification.Domain.PerseveranceCalculatorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.PerseveranceCalculator

  @recent_date "2026-06-16T10:00:00Z"

  describe "calculate/3" do
    test "returns 100.0 with no modifications" do
      assert 100.0 == PerseveranceCalculator.calculate([], [], ~D[2026-06-16])
    end

    test "returns 100.0 when actual matches prescribed" do
      mod = %{
        "exercise_id" => "ex1",
        "field" => "reps",
        "prescribed_value" => 10.0,
        "actual_value" => 10.0,
        "skipped" => false,
        "logged_at" => @recent_date
      }

      result = PerseveranceCalculator.calculate([mod], [], ~D[2026-06-16])
      assert result == 100.0
    end

    test "50% deviation gives 50.0 perseverance" do
      mod = %{
        "exercise_id" => "ex1",
        "field" => "reps",
        "prescribed_value" => 10.0,
        "actual_value" => 5.0,
        "skipped" => false,
        "logged_at" => @recent_date
      }

      result = PerseveranceCalculator.calculate([mod], [], ~D[2026-06-16])
      assert result == 50.0
    end

    test "skipped exercise contributes full deviation" do
      mod = %{
        "exercise_id" => "ex1",
        "field" => "reps",
        "prescribed_value" => 10.0,
        "actual_value" => nil,
        "skipped" => true,
        "logged_at" => @recent_date
      }

      result = PerseveranceCalculator.calculate([mod], [], ~D[2026-06-16])
      assert result <= 100.0 and result >= 0.0
    end

    test "modifications outside last 7 training days are excluded" do
      old_mod = %{
        "exercise_id" => "ex1",
        "field" => "reps",
        "prescribed_value" => 10.0,
        "actual_value" => 0.0,
        "skipped" => false,
        "logged_at" => "2026-05-01T10:00:00Z"
      }

      # Should return 100.0 because the old modification is excluded
      result = PerseveranceCalculator.calculate([old_mod], [], ~D[2026-06-16])
      assert result == 100.0
    end
  end
end
