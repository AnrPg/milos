defmodule MilosTraining.Workouts.Domain.WorkoutMaterializerTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.WorkoutMaterializer

  @scaled %{id: "scale-scaled", slug: "scaled", label: "Scaled", sort_order: 1}
  @rx %{id: "scale-rx", slug: "rx", label: "Rx", sort_order: 2}
  @competition %{
    id: "scale-competition",
    slug: "competition",
    label: "Competition",
    sort_order: 3
  }

  @base_workout %{
    id: "wod-a",
    sections: [
      %{
        id: "s1",
        exercises: [
          %{
            id: "e1",
            name: "Push-ups",
            sets: 1,
            prescription_value: 10,
            prescription_unit: "reps",
            variations: [
              %{
                scale_level: @scaled,
                prescription_value: 8,
                exercise_name_override: "Knee push-ups"
              },
              %{scale_level: @rx, prescription_value: 10}
            ]
          },
          %{
            id: "e2",
            name: "Pull-ups",
            sets: 1,
            prescription_value: 5,
            prescription_unit: "reps",
            variations: [
              %{
                scale_level: @scaled,
                prescription_value: 3,
                exercise_name_override: "Ring rows"
              },
              %{scale_level: @competition, prescription_value: 8, load_value: 20}
            ]
          }
        ]
      }
    ]
  }

  test "returns all scale levels that appear in at least one variation in configured order" do
    scales = WorkoutMaterializer.available_scales(@base_workout)

    assert Enum.map(scales, & &1.slug) == ["scaled", "rx", "competition"]
  end

  test "scaled instance overrides all scaled variations" do
    instance = WorkoutMaterializer.materialize(@base_workout, "scaled")
    e1 = get_exercise(instance, "e1")
    e2 = get_exercise(instance, "e2")

    assert instance.scale_level.slug == "scaled"
    assert e1.prescription_value == 8
    assert e1.name == "Knee push-ups"
    assert e2.prescription_value == 3
    assert e2.name == "Ring rows"
  end

  test "rx instance overrides only rx variations and falls back to base for the rest" do
    instance = WorkoutMaterializer.materialize(@base_workout, "rx")
    e1 = get_exercise(instance, "e1")
    e2 = get_exercise(instance, "e2")

    assert e1.prescription_value == 10
    assert e2.prescription_value == 5
  end

  test "competition instance overrides only competition variations" do
    instance = WorkoutMaterializer.materialize(@base_workout, "competition")
    e1 = get_exercise(instance, "e1")
    e2 = get_exercise(instance, "e2")

    assert e1.prescription_value == 10
    assert e2.prescription_value == 8
    assert e2.load_value == 20
  end

  defp get_exercise(instance, exercise_id) do
    instance.sections
    |> Enum.flat_map(& &1.exercises)
    |> Enum.find(&(&1.id == exercise_id))
  end
end
