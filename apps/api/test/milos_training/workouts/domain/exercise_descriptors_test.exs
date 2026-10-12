defmodule MilosTraining.Workouts.Domain.ExerciseDescriptorsTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.ExerciseDescriptors

  test "keeps catalog refs, resolves canonical names and skips headers" do
    workout = %{
      sections: [
        %{
          exercises: [
            %{name: "My squat label", exercise_ref: "back-squat", item_type: "exercise"},
            %{name: "Part A", item_type: "header"},
            %{name: "Pull-up", exercise_ref: nil, item_type: "exercise"}
          ]
        },
        %{"exercises" => [%{"name" => "Pushups", "item_type" => "exercise"}]},
        %{exercises: [%{name: "Sandbag shuffle", exercise_ref: "not-a-catalog-id"}]}
      ]
    }

    assert ExerciseDescriptors.from_workout(workout) == [
             %{name: "My squat label", exercise_ref: "back-squat", category: "strength"},
             %{name: "Pull-up", exercise_ref: "pull-up", category: "bodyweight"},
             %{name: "Pushups", exercise_ref: nil, category: nil},
             %{name: "Sandbag shuffle", exercise_ref: nil, category: nil}
           ]
  end

  test "a workout without sections has no descriptors" do
    assert ExerciseDescriptors.from_workout(%{}) == []
    assert ExerciseDescriptors.from_workout(nil) == []
  end
end
