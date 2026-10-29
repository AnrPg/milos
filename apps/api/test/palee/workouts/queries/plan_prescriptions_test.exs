defmodule Palee.Workouts.Queries.PlanPrescriptionsTest do
  @moduledoc "ADR-270: the port other contexts read plan workouts through."
  use ExUnit.Case, async: true

  import Palee.StructuredPlanFixtures

  alias Palee.Workouts.Domain.ExerciseDescriptors
  alias Palee.Workouts.Queries.PlanPrescriptions

  defp workout(plans) do
    %{
      authoring_mode: "structured_plan",
      sections:
        plans
        |> Enum.with_index(1)
        |> Enum.map(fn {plan, order} ->
          %{
            id: "s#{order}",
            name: "Section #{order}",
            scoreable: false,
            score_config: nil,
            plan: plan,
            exercises: []
          }
        end)
    }
  end

  test "workload reads the actuals of each section and the scored rounds of the others" do
    plans = [Enum.at(program(), 0), Enum.at(program(), 6), Enum.at(program(), 7)]
    workout = workout(plans)

    plan_sets = [
      %{
        section_id: "s1",
        row_id: "r1",
        block_index: 0,
        round_index: 1,
        phase_index: 0,
        interrupt: false,
        actual_reps: Decimal.new(12),
        actual_load_kg: Decimal.new(60),
        logged: true
      }
    ]

    workload =
      PlanPrescriptions.workload(workout, plan_sets,
        section_scores: [%{"section_id" => "s2", "value" => "2+5"}],
        section_elapsed_ms: %{"s3" => 250_000}
      )

    assert [%{section_id: "s1", source: "actuals"}, s2, s3] = workload.sections
    # AMRAP "2+5": 2 full rounds of 15 pull-ups and 5 + 10 snatches, then 5 pull-ups.
    assert %{source: "prescription", totals: %{reps: 50, volume_kg: 650}} = s2
    # 75 thrusters and an interruption at 2:00 and 4:00.
    assert %{totals: %{reps: 95}} = s3

    assert %{sets: 8.33, logged_sets: 1, reps: 157, volume_kg: 1370} = workload.totals

    assert Enum.map(workload.exercises, & &1.name) |> Enum.sort() ==
             ["Back Squat", "Burpee over Bar", "Butterfly Pull-up", "Power Snatch", "Thruster"]
  end

  test "workload and weights are empty for a workout without plans" do
    assert PlanPrescriptions.workload(%{sections: [%{id: "a", exercises: []}]}, []) == nil
    assert PlanPrescriptions.workload(nil) == nil
    assert PlanPrescriptions.exercise_weights(%{sections: []}) == []
    refute PlanPrescriptions.plan_workout?(%{authoring_mode: "structured"})
    assert PlanPrescriptions.plan_workout?(%{"authoring_mode" => "structured_plan"})
  end

  test "goal and coverage weights of a plan come from its prescribed sets, not its materialised rows" do
    workout =
      workout([Enum.at(program(), 5), Enum.at(program(), 1)])
      # Materialised rows say one set each; the plan says 4 minutes each.
      |> update_in([:sections, Access.at(0), :exercises], fn _ ->
        [%{name: "Wall Ball", sets: 1}]
      end)

    weights = ExerciseDescriptors.weighted_from_workout(workout)

    assert Enum.map(weights, &{&1.name, &1.weight}) == [
             {"Wall Ball", 4},
             {"Burpee to Target", 4},
             {"Knee Extension", 4},
             {"Standing Calf Raise", 4},
             {"Cyclist Squat", 4}
           ]

    assert [%{name: "Wall Ball", sets: 4} | _rest] = PlanPrescriptions.exercise_weights(workout)
  end
end
