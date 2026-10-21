defmodule Palee.Workouts.Domain.ExerciseDescriptorsTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.ExerciseDescriptors

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

  test "a materialized scale skips excluded exercises and resolves name overrides (TD-088)" do
    workout = %{
      sections: [
        %{
          exercises: [
            %{
              name: "Ring row",
              exercise_ref: "pull-up",
              applied_variation: %{exercise_name_override: "Ring row", excluded: false}
            },
            %{
              name: "Box jump",
              exercise_ref: "box-jump",
              excluded: true,
              applied_variation: %{excluded: true}
            },
            %{
              name: "Banded sandbag drag",
              exercise_ref: "deadlift",
              applied_variation: %{exercise_name_override: "Banded sandbag drag"}
            },
            %{name: "Back squat", exercise_ref: "back-squat", applied_variation: nil}
          ]
        }
      ]
    }

    assert ExerciseDescriptors.from_workout(workout) == [
             %{name: "Ring row", exercise_ref: "ring-row", category: "bodyweight"},
             %{name: "Banded sandbag drag", exercise_ref: nil, category: nil},
             %{name: "Back squat", exercise_ref: "back-squat", category: "strength"}
           ]
  end

  test "a variation without a name override keeps the base exercise ref" do
    workout = %{
      sections: [
        %{
          exercises: [
            %{
              name: "Deadlift",
              exercise_ref: "deadlift",
              applied_variation: %{exercise_name_override: nil, load_value: 40}
            }
          ]
        }
      ]
    }

    assert [%{exercise_ref: "deadlift"}] = ExerciseDescriptors.from_workout(workout)
  end

  test "a workout without sections has no descriptors" do
    assert ExerciseDescriptors.from_workout(%{}) == []
    assert ExerciseDescriptors.from_workout(nil) == []
  end
end
