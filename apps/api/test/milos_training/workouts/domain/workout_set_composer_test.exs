defmodule MilosTraining.Workouts.Domain.WorkoutSetComposerTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.WorkoutSetComposer

  test "expands a progressive deload into concrete per-set prescriptions" do
    exercise = %{
      item_type: "exercise",
      name: "Back squat",
      sets: 3,
      prescription_value: 8,
      prescription_unit: "reps",
      load_mode: "pct_1rm",
      load_progression: %{
        "mode" => "linear",
        "direction" => "decrease",
        "start_value" => 80,
        "start_mode" => "pct_1rm",
        "step_value" => 5
      }
    }

    assert {:ok, normalized} = WorkoutSetComposer.normalize_items([exercise])

    assert [
             %{set_index: 1, prescription_value: 8, load_value: 80, load_mode: "pct_1rm"},
             %{set_index: 2, prescription_value: 8, load_value: 75, load_mode: "pct_1rm"},
             %{set_index: 3, prescription_value: 8, load_value: 70, load_mode: "pct_1rm"}
           ] = hd(normalized).set_prescriptions
  end

  test "preserves different repetitions and loads for every set" do
    exercise = %{
      item_type: "exercise",
      name: "Deadlift",
      sets: 3,
      prescription_value: 5,
      prescription_unit: "reps",
      set_prescriptions: [
        %{"set_index" => 1, "prescription_value" => 5, "load_value" => 120},
        %{"set_index" => 2, "prescription_value" => 3, "load_value" => 130},
        %{"set_index" => 3, "prescription_value" => 1, "load_value" => 140}
      ],
      load_mode: "absolute"
    }

    assert {:ok, [normalized]} = WorkoutSetComposer.normalize_items([exercise])
    assert Enum.map(normalized.set_prescriptions, & &1.prescription_value) == [5, 3, 1]
    assert Enum.map(normalized.set_prescriptions, & &1.load_value) == [120, 130, 140]
  end

  test "accepts supersets and alternating groups with more than two exercises" do
    superset_id = Ecto.UUID.generate()
    alternating_id = Ecto.UUID.generate()

    items = [
      exercise("A", superset_group_id: superset_id),
      exercise("B", superset_group_id: superset_id),
      exercise("C", alternating_group_id: alternating_id),
      exercise("D", alternating_group_id: alternating_id),
      exercise("E", alternating_group_id: alternating_id)
    ]

    assert {:ok, normalized} = WorkoutSetComposer.normalize_items(items)
    assert Enum.count(normalized, &(&1.superset_group_id == superset_id)) == 2
    assert Enum.count(normalized, &(&1.alternating_group_id == alternating_id)) == 3
  end

  test "rejects one-member groups and rows assigned to both group types" do
    group_id = Ecto.UUID.generate()

    assert {:error, :superset_requires_multiple_items} =
             WorkoutSetComposer.normalize_items([
               exercise("A", superset_group_id: group_id)
             ])

    assert {:error, :ambiguous_set_group} =
             WorkoutSetComposer.normalize_items([
               exercise("A",
                 superset_group_id: group_id,
                 alternating_group_id: Ecto.UUID.generate()
               ),
               exercise("B", superset_group_id: group_id)
             ])
  end

  test "headers remain ordered presentation items and cannot join a group" do
    header = %{
      item_type: "header",
      name: "Accessory work",
      note: "Keep transitions short",
      superset_group_id: Ecto.UUID.generate()
    }

    assert {:error, :header_cannot_join_set_group} =
             WorkoutSetComposer.normalize_items([header])

    assert {:ok, [normalized]} =
             WorkoutSetComposer.normalize_items([
               %{item_type: "header", name: "Accessory work", note: "Keep transitions short"}
             ])

    assert normalized.item_type == "header"
    assert normalized.set_prescriptions == []
    assert normalized.note == "Keep transitions short"
  end

  defp exercise(name, attrs) do
    attrs
    |> Map.new()
    |> Map.merge(%{
      item_type: "exercise",
      name: name,
      sets: 2,
      prescription_value: 10,
      prescription_unit: "reps"
    })
  end
end
