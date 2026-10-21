defmodule Palee.Workouts.Domain.WorkoutIconTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.WorkoutIcon

  test "accepts exactly one emoji, including multi-code-point ones" do
    assert WorkoutIcon.normalize(" 💆 ") == {:ok, "💆"}
    assert WorkoutIcon.normalize("🏋️‍♀️") == {:ok, "🏋️‍♀️"}
    assert WorkoutIcon.normalize("⏱️") == {:ok, "⏱️"}
  end

  test "rejects text, several emoji and empty values" do
    assert WorkoutIcon.normalize("A") == :error
    assert WorkoutIcon.normalize("🔥🔥") == :error
    assert WorkoutIcon.normalize("Sure! 🏋️") == :error
    assert WorkoutIcon.normalize("") == :error
    assert WorkoutIcon.normalize(nil) == :error
  end
end
