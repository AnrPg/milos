defmodule Palee.Workouts.GoalExercisesTest do
  @moduledoc "ADR-163: exercises read from a workout for WOD-goal suggestion."
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.{ExerciseDescriptors, FreeTextExercises}

  describe "FreeTextExercises.from_text/1" do
    test "finds catalog movements in free text, plurals and loads included" do
      text = """
      For time:
      21-15-9
      Thrusters (43/30 kg)
      Pull-ups
      """

      assert [
               %{exercise_ref: "thruster", weight: 1},
               %{exercise_ref: "pull-up", weight: 1}
             ] = FreeTextExercises.from_text(text)
    end

    test "reads a leading sets x reps as the set count and several movements per line" do
      assert [%{exercise_ref: "back-squat", weight: 5}] =
               FreeTextExercises.from_text("5x5 Back Squat @ 80%")

      assert [%{exercise_ref: "box-jump"}, %{exercise_ref: "burpee"}] =
               FreeTextExercises.from_text("10 box jumps then 10 burpees")
    end

    test "a line naming nothing known is one unmatched exercise" do
      assert [%{exercise_ref: nil, name: "Partner carry relay"}] =
               FreeTextExercises.from_text("Partner carry relay")

      assert FreeTextExercises.from_text("  \n 12 \n") == []
      assert FreeTextExercises.from_text(nil) == []
    end

    test "keeps multi-word names whole (clean and jerk is not clean + jerk)" do
      assert [%{exercise_ref: "clean-and-jerk"}] =
               FreeTextExercises.from_text("Clean and Jerk 1RM")
    end
  end

  describe "ExerciseDescriptors.weighted_from_workout/1" do
    test "structured sections weigh by sets and resolve plural names" do
      workout = %{
        sections: [
          %{
            exercises: [
              %{name: "Air Squats", sets: 3},
              %{name: "Header", item_type: "header"},
              %{name: "Deadlift", exercise_ref: "deadlift", sets: nil},
              %{"name" => "Mystery move", "sets" => 2}
            ]
          }
        ]
      }

      assert [
               %{exercise_ref: "air-squat", weight: 3},
               %{exercise_ref: "deadlift", weight: 1},
               %{exercise_ref: nil, weight: 2}
             ] = ExerciseDescriptors.weighted_from_workout(workout)
    end

    test "falls back to the free-text body, also a draft's" do
      assert [%{exercise_ref: "row"}] =
               ExerciseDescriptors.weighted_from_workout(%{sections: [], free_text_body: "Row"})

      assert [%{exercise_ref: "burpee"}] =
               ExerciseDescriptors.weighted_from_workout(%{
                 sections: [],
                 draft_data: %{"free_text_body" => "Burpees"}
               })
    end
  end
end
