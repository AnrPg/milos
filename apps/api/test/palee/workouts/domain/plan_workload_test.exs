defmodule Palee.Workouts.Domain.PlanWorkloadTest do
  @moduledoc "ADR-270: what a structured plan section means for volume, sets and time."
  use ExUnit.Case, async: true

  import Palee.StructuredPlanFixtures

  alias Palee.Workouts.Domain.PlanWorkload

  defp plan(index), do: Enum.at(program(), index)
  defp by_name(workload), do: Map.new(workload.exercises, &{&1.name, &1})

  describe "from the prescription" do
    test "a sets flow counts each set with its own reps and kg; % loads need a 1RM" do
      # Back Squat 12 @60%, 10 @+5, 8, 8 (the +5 keeps adding): 60/65/70/75 % of 100 kg.
      with_orm = PlanWorkload.section(plan(0), [], one_rep_max: fn "Back Squat", nil -> 100 end)

      assert %{source: "prescription", flow: "sets", totals: totals} = with_orm
      assert %{sets: 4, reps: 38, volume_kg: 2530, estimated: false} = totals
      assert [%{name: "Back Squat", top_set: %{load_kg: 75, reps: 8}}] = with_orm.exercises

      # Without the athlete's 1RM the % load has no kg: reps count, volume does not.
      without = PlanWorkload.section(plan(0))
      assert %{reps: 38, volume_kg: 0, estimated: true} = without.totals
    end

    test "a superset of 3-4 sets counts the optional set as half, rep ranges at their midpoint" do
      workload = PlanWorkload.section(plan(1))
      rows = by_name(workload)

      assert %{sets: 3.5, reps: 47.25, estimated: true} = rows["Knee Extension"]
      assert %{sets: 3.5, reps: 52.5} = rows["Standing Calf Raise"]
      assert Enum.all?(workload.exercises, &(&1.group_id == "g1"))
      assert workload.totals.sets == 10.5
    end

    test "rest rows are no exercises, max effort has no reps, words carry no kg" do
      rows = by_name(PlanWorkload.section(plan(2)))

      assert Map.keys(rows) |> Enum.sort() == ["Echo Bike", "Ring Dip", "Strict HSPU"]
      assert %{sets: 4, reps: 28, volume_kg: 0} = rows["Ring Dip"]
      assert %{reps: 0, calories: 0, estimated: true} = rows["Echo Bike"]
    end

    test "a cluster does its reps in every piece" do
      workload = PlanWorkload.section(plan(3), [], one_rep_max: fn _name, _ref -> 100 end)

      # 5 sets × 3 clusters × 3 reps @ 80 kg.
      assert %{sets: 5, reps: 45, volume_kg: 3600} = workload.totals
    end

    test "a drop set repeats its reps at a lower load" do
      section =
        section(
          "sets",
          %{"sets" => "2"},
          [[ex("d1", "Curl", "", "", %{"cells" => cells([{"10", "20kg"}])})]],
          %{
            "structs" => %{"d1" => %{"kind" => "drop", "drops" => "2", "dropby" => "25%"}}
          }
        )

      # Each set: 10 @ 20, 10 @ 15, 10 @ 11.25.
      assert %{reps: 60, volume_kg: 925} = PlanWorkload.section(section).totals
    end

    test "EMOM rounds of two kinds count each in its own minutes" do
      workload = PlanWorkload.section(plan(5))
      rows = by_name(workload)

      assert %{sets: 4, reps: 80, block_index: 0} = rows["Wall Ball"]
      assert %{sets: 4, reps: 48, block_index: 1} = rows["Burpee to Target"]
      assert workload.time_domain == %{planned_secs: 480, cap_secs: nil, open_ended: false}
    end

    test "per side rows count both sides; 4×8-10 in a sets flow is the flow's sets" do
      rows = by_name(PlanWorkload.section(plan(13)))

      # 4 sets × 9 reps (8-10) × 2 sides @ 22.5 kg.
      assert %{per_side: true, sets: 4, reps: 72, volume_kg: 1620, estimated: true} =
               rows["Bulgarian Split Squat"]
    end

    test "4×10 in a row of another flow is four sets each round" do
      section = section("for_time", %{"rounds" => "2"}, [[ex("x1", "Push-up", "4x10")]])

      assert %{sets: 8, reps: 80} = PlanWorkload.section(section).totals
    end

    test "distance, calories and time go to their own amounts" do
      rows = by_name(PlanWorkload.section(plan(8)))

      assert %{distance_m: 1000, reps: 0, sets: 2} = rows["Row"]
      assert %{distance_m: 800} = rows["Run"]
      assert %{reps: 40} = rows["Wall Ball"]

      hold =
        section("sets", %{"sets" => "3"}, [
          [ex("h1", "Plank", "", "", %{"cells" => [%{"d" => "60s"}]})]
        ])

      assert %{work_secs: 180, reps: 0} = PlanWorkload.section(hold).totals
    end

    test "an open-ended AMRAP counts the scored rounds and follows the plan after the written ones" do
      # Power Snatch 5 @ 40, 10 @ +5 kg, 15 (then +5 kg each round); pull-ups 15 every round.
      workload = PlanWorkload.section(plan(6), [], rounds_done: 5)
      rows = by_name(workload)

      assert %{sets: 5, reps: 75} = rows["Butterfly Pull-up"]
      # 5×40 + 10×45 + 15×50 + 15×55 + 15×60
      assert %{sets: 5, reps: 60, volume_kg: 3125, top_set: %{load_kg: 60, reps: 15}} =
               rows["Power Snatch"]

      assert workload.open_ended
      refute workload.totals.estimated

      # "5-10-15…" keeps adding 5 reps.
      thrusters = PlanWorkload.section(plan(12), [], rounds_done: 5)
      assert %{reps: 75, volume_kg: 1687.5} = thrusters.totals
    end

    test "an open-ended section without a score counts the written rounds as an estimate" do
      workload = PlanWorkload.section(plan(6))

      assert %{estimated: true} = workload.totals
      assert %{sets: 3, reps: 30} = by_name(workload)["Power Snatch"]
    end

    test "interruption rows fire in the time spent" do
      workload = PlanWorkload.section(plan(7), [], elapsed_secs: 7 * 60 + 30)

      assert %{sets: 3, reps: 30, interrupt: true, block_index: -1} =
               by_name(workload)["Burpee over Bar"]

      # No time known and no cap: nothing to count.
      refute Map.has_key?(by_name(PlanWorkload.section(plan(7))), "Burpee over Bar")
    end

    test "time domains of every flow" do
      domain = fn index -> PlanWorkload.section(plan(index)).time_domain end

      assert %{planned_secs: nil, cap_secs: nil, open_ended: false} = domain.(0)
      assert %{planned_secs: 600} = domain.(4)
      assert %{planned_secs: 420, open_ended: true} = domain.(6)
      assert %{planned_secs: nil, cap_secs: 1200} = domain.(8)
      # 3+3+3+4 minutes and a minute between windows.
      assert %{planned_secs: 960} = domain.(9)
      # Heart-rate rests: no fixed length.
      assert %{planned_secs: nil} = domain.(10)
      assert %{planned_secs: 120} = domain.(11)

      tabata =
        section("intervals", %{"work" => "20″", "off" => "10″", "rounds" => "8"}, [
          [ex("t", "Row", "max cal")]
        ])

      assert %{planned_secs: 230} = PlanWorkload.section(tabata).time_domain
    end

    test "a section without exercises counts nothing; not a plan is nil" do
      assert %{exercises: [], totals: %{sets: 0}} = PlanWorkload.section(plan(11))
      assert PlanWorkload.section(%{"flow" => "nope"}) == nil
      assert PlanWorkload.section(nil) == nil
    end
  end

  describe "from the actuals" do
    defp actual(row_id, round, more) do
      Map.merge(
        %{
          section_id: "s1",
          row_id: row_id,
          exercise_name: "Back Squat",
          exercise_ref: nil,
          block_index: 0,
          round_index: round,
          part_index: 0,
          phase_index: 0,
          interrupt: false,
          prescribed_reps: nil,
          prescribed_load_kg: nil,
          prescribed_load_pct: nil,
          one_rep_max_kg: nil,
          actual_reps: nil,
          actual_load_kg: nil,
          logged: false
        },
        more
      )
    end

    test "count what was done, logged or as prescribed, with % loads through the runner's 1RM" do
      actuals = [
        actual("r1", 1, %{
          actual_reps: Decimal.new(12),
          actual_load_kg: Decimal.new("62.5"),
          logged: true
        }),
        actual("r1", 2, %{
          actual_reps: 10,
          prescribed_load_pct: 65,
          one_rep_max_kg: 100,
          logged: false
        })
      ]

      workload = PlanWorkload.section(plan(0), actuals)

      assert %{source: "actuals"} = workload
      # 12 × 62.5 + 10 × 65; the two sets never done do not count.
      assert %{sets: 2, logged_sets: 1, reps: 22, volume_kg: 1400, estimated: false} =
               workload.totals
    end

    test "a value the record lacks comes from the prescription of its round" do
      actuals = [
        actual("r2", 1, %{exercise_name: "Knee Extension"}),
        actual("r19", 1, %{exercise_name: "Row", actual_reps: nil})
      ]

      rows = by_name(PlanWorkload.section(plan(1), Enum.take(actuals, 1)))
      assert %{sets: 1, reps: 13.5, estimated: true} = rows["Knee Extension"]

      rows = by_name(PlanWorkload.section(plan(8), Enum.drop(actuals, 1)))
      assert %{sets: 1, distance_m: 500, reps: 0} = rows["Row"]
    end

    test "an AMRAP counts the rounds done, including rounds past the written ones" do
      actuals =
        for round <- 1..4 do
          actual("r16", round, %{exercise_name: "Power Snatch", actual_reps: nil})
        end

      # 5×40 + 10×45 + 15×50 + 15×55 (the 4th round follows the +5 kg rule).
      rows = by_name(PlanWorkload.section(plan(6), actuals))
      assert %{sets: 4, reps: 45, volume_kg: 2225} = rows["Power Snatch"]
      refute Map.has_key?(rows, "Butterfly Pull-up")
    end

    test "parts of one set are one set; interruption rows count per interruption" do
      actuals =
        for part <- 0..2 do
          actual("r10", 1, %{part_index: part, actual_reps: 3, actual_load_kg: 80})
        end ++
          [
            actual("r18", 1, %{
              exercise_name: "Burpee over Bar",
              block_index: -1,
              interrupt: true,
              actual_reps: 10
            }),
            actual("r18", 2, %{
              exercise_name: "Burpee over Bar",
              block_index: -1,
              interrupt: true,
              actual_reps: 8
            })
          ]

      assert %{sets: 1, reps: 9, volume_kg: 720} =
               PlanWorkload.section(plan(3), Enum.take(actuals, 3)).totals

      rows = by_name(PlanWorkload.section(plan(7), Enum.drop(actuals, 3)))
      assert %{sets: 2, reps: 18, interrupt: true} = rows["Burpee over Bar"]
    end

    test "records of a row the plan no longer has count what they say" do
      actuals = [
        actual("gone", 1, %{exercise_name: "Deadlift", actual_reps: 5, actual_load_kg: 100})
      ]

      assert [%{name: "Deadlift", sets: 1, reps: 5, volume_kg: 500}] =
               PlanWorkload.section(plan(0), actuals).exercises
    end

    test "string keys and JSON numbers read the same" do
      record = %{
        "section_id" => "s1",
        "row_id" => "r1",
        "block_index" => 0,
        "round_index" => 1,
        "actual_reps" => 12,
        "actual_load_kg" => 60.5,
        "logged" => true
      }

      assert %{reps: 12, volume_kg: 726, logged_sets: 1} =
               PlanWorkload.section(plan(0), [record]).totals
    end
  end

  test "exercise weights are the prescribed sets of each exercise row" do
    assert [
             %{row_id: "r11", name: "Front Squat", sets: 4},
             %{row_id: "r12", name: "Dual DB Push Press", sets: 4}
           ] = PlanWorkload.exercise_weights(plan(4))

    assert [%{sets: 4}, %{sets: 4}, %{sets: 4}] = PlanWorkload.exercise_weights(plan(1))
    assert PlanWorkload.exercise_weights(plan(11)) == []
    assert PlanWorkload.exercise_weights(nil) == []
  end

  test "rounds from a score" do
    assert PlanWorkload.rounds_from_score("5+3") == 5
    assert PlanWorkload.rounds_from_score(" 7 ") == 7
    assert PlanWorkload.rounds_from_score(6) == 6
    assert PlanWorkload.rounds_from_score("12:30") == nil
    assert PlanWorkload.rounds_from_score(nil) == nil
  end

  test "merge sums sections and the same exercise across them" do
    orm = fn _name, _ref -> 100 end
    a = PlanWorkload.section(plan(0), [], one_rep_max: orm)
    b = PlanWorkload.section(plan(3), [], one_rep_max: orm)

    assert %{totals: totals, exercises: [squat]} = PlanWorkload.merge([a, nil, b])
    assert %{sets: 9, reps: 83, volume_kg: 6130, estimated: false} = totals
    assert %{name: "Back Squat", sets: 9, top_set: %{load_kg: 80, reps: 3}} = squat
  end
end
