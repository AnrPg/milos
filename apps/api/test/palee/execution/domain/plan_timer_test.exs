defmodule Palee.Execution.Domain.PlanTimerTest do
  use ExUnit.Case, async: true

  import Palee.StructuredPlanFixtures

  alias Palee.Execution
  alias Palee.Execution.Domain.{ClassTimerMachine, PlanTimer, ProgressSnapshotter, ScoreRanking}

  defp sections(indexes) do
    indexes
    |> Enum.with_index(1)
    |> Enum.map(fn {index, order} ->
      %{id: "s#{order}", name: "Part #{order}", order: order, plan: Enum.at(program(), index)}
    end)
  end

  test "one segment per plan section, keyed like the web, with the section's score" do
    [strength, engine] = PlanTimer.build(sections([0, 7]))

    assert %{
             segment_key: "plan:s1",
             section_id: "s1",
             format: "structured_plan",
             kind: :countup,
             duration_seconds: nil
           } = strength

    assert %{
             segment_key: "plan:s2",
             kind: :countup,
             scoreable: true,
             score_config: %{type: "time", label: "Part 2"},
             timer_config: %{plan_flow: "for_time", interrupt_every_seconds: 120}
           } = engine
  end

  test "the clock becomes a timer the class timer can run" do
    emom = section("emom", %{"every" => "1:00", "times" => "10"}, [[ex("e", "Burpee", "10")]])
    amrap = Enum.at(program(), 9)
    rest = Enum.at(program(), 11)

    intervals =
      section("intervals", %{"work" => "0:40", "off" => "0:20", "rounds" => "5"}, [
        [ex("i", "Row", "max", "", %{})]
      ])

    [e, a, r, i] =
      PlanTimer.build([
        %{id: "e", plan: emom, order: 1},
        %{id: "a", plan: amrap, order: 2},
        %{id: "r", plan: rest, order: 3},
        %{id: "i", plan: intervals, order: 4}
      ])

    assert %{kind: :interval_cycle, duration_seconds: 60, total_rounds: 10} = e
    assert ClassTimerMachine.segment_limit_ms(e) == 600_000

    # Four windows with rest between them: the whole block counts down.
    assert %{kind: :countdown, timer_config: %{amrap_windows_seconds: [180, 180, 180, 240]}} = a
    assert a.duration_seconds >= 780

    assert %{kind: :countdown, phase: "rest", duration_seconds: 120, scoreable: false} = r

    assert %{
             kind: :interval_cycle,
             total_rounds: 9,
             timer_config: %{interval_pattern_seconds: [40, 20]}
           } =
             i

    # 5 × (40 + 20) − the off after the last work window.
    assert ClassTimerMachine.segment_limit_ms(i) == 280_000

    work_only =
      section("intervals", %{"work" => "1:00", "rounds" => "3"}, [
        [ex("w", "Row", "max", "", %{})]
      ])

    assert [%{total_rounds: 3, timer_config: %{interval_pattern_seconds: [60]}} = w] =
             PlanTimer.build([%{id: "w", plan: work_only}])

    assert ClassTimerMachine.segment_limit_ms(w) == 180_000
  end

  test "an open-ended EMOM has no last window" do
    open = section("emom", %{"every" => "1:00", "times" => ""}, [[ex("d", "Burpee", "1-2-3…")]])

    assert [%{kind: :interval_cycle, total_rounds: nil, timer_config: %{open_ended: true}}] =
             PlanTimer.build([%{id: "d", plan: open}])
  end

  test "a structured_plan workout runs its plan segments; completion accepts the plan score" do
    workout = %{authoring_mode: "structured_plan", sections: sections([0, 7])}
    segments = Execution.build_timer_sequence(workout)
    assert Enum.map(segments, & &1.segment_key) == ["plan:s1", "plan:s2"]

    score = %{section_id: "s2", value: 754, score_type: "time"}
    assert :ok = ProgressSnapshotter.validate_manual_scores(segments, [score])

    assert :ok !=
             ProgressSnapshotter.validate_manual_scores(segments, [%{score | score_type: "reps"}])

    assert [%{section_id: "s2", value: 754}] =
             ProgressSnapshotter.final_snapshots(segments, %{}, [score])
  end

  test "sections without a plan are skipped" do
    assert PlanTimer.build([%{id: "x", plan: nil}, %{"id" => "y"}]) == []
    assert PlanTimer.build(nil) == []
  end

  test "a plan's rounds + reps score ranks like rounds+reps" do
    assert ScoreRanking.sort_value(%{"value" => "5+3"}, "rounds_reps") ==
             ScoreRanking.sort_value(%{"value" => "5+3"}, "rounds+reps")

    assert ScoreRanking.sort_value(%{"value" => "5+3"}, "rounds_reps") >
             ScoreRanking.sort_value(%{"value" => "4+20"}, "rounds_reps")
  end
end
