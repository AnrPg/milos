defmodule MilosTraining.Workouts.Domain.WorkoutFocusTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.WorkoutFocus

  defp workout(names) do
    %{sections: [%{exercises: Enum.map(names, &%{name: &1, item_type: :exercise})}]}
  end

  test "a leg strength day with a little core stays a leg strength day" do
    focus =
      WorkoutFocus.from_workout(workout(["Back Squat", "Romanian Deadlift", "Lunge", "Sit-up"]))

    assert "strength" in focus
    assert "legs" in focus
    refute "core" in focus
  end

  test "any olympic lift makes it an olympic lifting session" do
    focus =
      WorkoutFocus.from_workout(workout(["Run", "Row", "Burpee", "Air Bike", "Power Snatch"]))

    assert "olympic_lifting" in focus
    assert "endurance" in focus
  end

  test "gymnastics and upper body come from the movements" do
    assert WorkoutFocus.from_workout(workout(["Pull-up", "Handstand Push-up", "Ring Dip"])) ==
             ["gymnastics", "upper_body"]
  end

  test "headers, excluded and unknown movements are ignored" do
    workout = %{
      sections: [
        %{
          exercises: [
            %{name: "Warm-up", item_type: :header},
            %{name: "Back Squat", item_type: :exercise, excluded: true},
            %{name: "Zorbing", item_type: :exercise}
          ]
        }
      ]
    }

    assert WorkoutFocus.from_workout(workout) == []
    assert WorkoutFocus.from_workout(nil) == []
  end
end
