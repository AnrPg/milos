defmodule Palee.Workouts.Domain.StructuredPlanWorkoutTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.StructuredPlanWorkout

  import Palee.StructuredPlanFixtures

  test "only a structured_plan workout is one" do
    assert StructuredPlanWorkout.plan?(%{"authoring_mode" => "structured_plan"})
    assert StructuredPlanWorkout.plan?(%{authoring_mode: "structured_plan"})
    refute StructuredPlanWorkout.plan?(%{authoring_mode: "structured"})
    refute StructuredPlanWorkout.plan?(nil)
  end

  test "per-set rows: first column reps and load, sets, tempo and note" do
    [squat] = StructuredPlanWorkout.exercises(Enum.at(program(), 0))

    assert squat == %{
             "item_type" => "exercise",
             "name" => "Back Squat",
             "exercise_ref" => nil,
             "note" => "Έλεγχος στο κατέβασμα, με ζώνη",
             "tempo" => "31X1",
             "superset_group_id" => nil,
             "sets" => 4,
             "prescription_value" => 12,
             "prescription_unit" => "reps",
             "load_value" => 60,
             "load_mode" => "pct_1rm"
           }
  end

  test "a group of exercises shares a stable superset id; rest rows are not exercises" do
    [a, b, c] = StructuredPlanWorkout.exercises(Enum.at(program(), 1))
    group = StructuredPlanWorkout.group_uuid("g1")

    assert Enum.map([a, b, c], & &1["superset_group_id"]) == [group, group, group]
    assert {:ok, _uuid} = Ecto.UUID.cast(group)
    assert StructuredPlanWorkout.group_uuid("g1") == group
    refute StructuredPlanWorkout.group_uuid("g2") == group
    # A range is not a whole number: no reps; "3-4" sets count as 4.
    refute Map.has_key?(a, "prescription_value")
    assert a["sets"] == 4
    assert c["note"] == "Φτέρνες ψηλά"

    names = program() |> Enum.at(2) |> StructuredPlanWorkout.exercises() |> Enum.map(& &1["name"])
    assert names == ["Ring Dip", "Strict HSPU", "Echo Bike"]
  end

  test "same-every-round rows, per-round rows, blocks in order, interruptions after" do
    [front, press] = StructuredPlanWorkout.exercises(Enum.at(program(), 4))
    assert front["prescription_value"] == 7
    refute Map.has_key?(press, "load_value")
    assert front["sets"] == nil

    assert ["Wall Ball", "Burpee to Target"] ==
             program()
             |> Enum.at(5)
             |> StructuredPlanWorkout.exercises()
             |> Enum.map(& &1["name"])

    [_pull, snatch] = StructuredPlanWorkout.exercises(Enum.at(program(), 6))
    assert %{"prescription_value" => 5, "load_value" => 40, "load_mode" => "absolute"} = snatch

    assert ["Thruster", "Burpee over Bar"] ==
             program()
             |> Enum.at(7)
             |> StructuredPlanWorkout.exercises()
             |> Enum.map(& &1["name"])

    [row, _burpee, run, _wall] = StructuredPlanWorkout.exercises(Enum.at(program(), 8))
    assert %{"prescription_value" => 500, "prescription_unit" => "meters"} = row
    assert run["prescription_value"] == 400

    [bike, _wb, clean] = StructuredPlanWorkout.exercises(Enum.at(program(), 9))
    assert %{"prescription_value" => 15, "prescription_unit" => "kcal"} = bike
    assert %{"load_value" => 60, "load_mode" => "absolute"} = clean
    refute Map.has_key?(clean, "prescription_value")

    assert StructuredPlanWorkout.exercises(Enum.at(program(), 11)) == []
  end

  test "decimal loads and unnamed rows are left out of the legacy columns" do
    plan = %{
      "v" => 1,
      "flow" => "for_time",
      "params" => %{},
      "score" => "time",
      "blocks" => [
        [
          %{
            "id" => "a",
            "kind" => "ex",
            "name" => "Snatch",
            "dose" => "4x3",
            "load" => "22.5kg",
            "cells" => []
          },
          %{
            "id" => "b",
            "kind" => "ex",
            "name" => "  ",
            "dose" => "1",
            "load" => "",
            "cells" => []
          },
          %{
            "id" => "c",
            "kind" => "ex",
            "name" => "Pull-up",
            "dose" => "10",
            "load" => "BW",
            "exerciseRef" => "ex-1",
            "group" => "solo"
          }
        ]
      ]
    }

    assert [snatch, pull] = StructuredPlanWorkout.exercises(plan)
    assert snatch["sets"] == 4
    assert snatch["prescription_value"] == 3
    refute Map.has_key?(snatch, "load_value")
    assert %{"load_mode" => "bw", "exercise_ref" => "ex-1", "superset_group_id" => nil} = pull
  end

  test "prepare keeps the key style and materialises every section" do
    params = %{
      authoring_mode: "structured_plan",
      sections: [
        %{name: "A", order: 1, plan: Enum.at(program(), 0), exercises: [%{name: "ignored"}]},
        %{"name" => "B", "order" => 2, "plan" => Enum.at(program(), 1)}
      ]
    }

    assert {:ok, %{sections: [a, b]}} = StructuredPlanWorkout.prepare(params)
    assert [%{"name" => "Back Squat"}] = a["exercises"]
    assert a["plan"]["flow"] == "sets"
    assert length(b["exercises"]) == 3

    assert {:ok, %{"sections" => [_one]}} =
             StructuredPlanWorkout.prepare(%{"sections" => [%{"plan" => Enum.at(program(), 0)}]})
  end

  test "prepare names every section whose plan does not read" do
    bad = Map.put(Enum.at(program(), 0), "flow", "crossfit")

    assert {:error, {:invalid_plan_sections, problems}} =
             StructuredPlanWorkout.prepare(%{sections: [%{name: "A"}, %{name: "B", plan: bad}]})

    assert problems == [
             %{section: 1, path: "", code: "plan_required"},
             %{section: 2, path: "flow", code: "unknown_flow"}
           ]

    assert StructuredPlanWorkout.prepare(%{sections: []}) == {:error, :no_sections}
  end
end
