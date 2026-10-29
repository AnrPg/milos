defmodule Palee.Execution.Domain.ExecutionAnalyticsTest do
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.ExecutionAnalytics

  @now ~U[2026-10-12 12:00:00.000000Z]

  defp segments do
    [
      %{section_id: "warmup", format: "untimed", kind: :manual, scoreable: false},
      %{section_id: "wod", format: "amrap", kind: :countdown, scoreable: true},
      %{section_id: "wod", format: "amrap", kind: :countdown, scoreable: true},
      %{section_id: "finisher", format: "for_time", kind: :countup, scoreable: true}
    ]
  end

  test "completion facts separate manual from automatic scores on scoreable sections" do
    execution = %{
      started_at_utc: ~U[2026-10-12 11:00:00.000000Z],
      completed_at_utc: ~U[2026-10-12 11:30:00.000000Z],
      total_elapsed_ms: 1_700_000,
      checked_exercise_ids: ["a", "b"],
      section_scores: [
        %{"section_id" => "wod", "value" => "5+3", "source" => "manual"},
        %{"section_id" => "finisher", "value" => "4:10", "source" => "auto"},
        %{"section_id" => "warmup", "value" => "x", "source" => "manual"}
      ]
    }

    assert ExecutionAnalytics.completion_facts(execution, segments()) == %{
             duration_ms: 1_800_000,
             total_elapsed_ms: 1_700_000,
             segment_count: 4,
             section_count: 3,
             scoreable_section_count: 2,
             manually_scored_section_count: 1,
             auto_scored_section_count: 1,
             checked_exercise_count: 2,
             primary_format: "untimed"
           }
  end

  test "abandonment facts report the format and index of the last snapshot" do
    execution = %{
      started_at_utc: ~U[2026-10-12 04:00:00.000000Z],
      completed_at_utc: nil,
      current_segment_index: 2,
      total_elapsed_ms: 400_000,
      checked_exercise_ids: [],
      last_progress_at: ~U[2026-10-12 04:20:00.000000Z]
    }

    facts = ExecutionAnalytics.abandonment_facts(execution, segments(), @now)

    assert facts.abandon_segment_index == 2
    assert facts.abandon_format == "amrap"
    assert facts.abandon_segment_kind == "countdown"
    assert facts.segment_count == 4
    assert facts.abandon_progress_pct == 50
    assert facts.hours_since_start == 8
    assert facts.had_progress_update
    assert facts.minutes_since_last_progress == 460
  end

  test "an index beyond the sequence yields no format rather than crashing" do
    facts =
      ExecutionAnalytics.abandonment_facts(
        %{started_at_utc: @now, current_segment_index: 99},
        [],
        @now
      )

    assert facts.abandon_format == nil
    assert facts.abandon_progress_pct == nil
    refute facts.had_progress_update
  end

  test "abandoned?/3 applies the threshold to uncompleted executions only" do
    started = ~U[2026-10-12 05:00:00.000000Z]

    assert ExecutionAnalytics.abandoned?(%{started_at_utc: started}, @now, 6)
    refute ExecutionAnalytics.abandoned?(%{started_at_utc: started}, @now, 8)

    refute ExecutionAnalytics.abandoned?(
             %{started_at_utc: started, completed_at_utc: @now},
             @now,
             6
           )
  end

  test "ADR-270: a plan execution adds what it recorded set by set" do
    sets = [
      %{section_id: "s", row_id: "r1", actual_reps: 5, actual_load_kg: 100, logged: true, interrupt: false},
      %{section_id: "s", row_id: "r1", actual_reps: 5, actual_load_kg: 102.5, logged: false, interrupt: false},
      %{"section_id" => "s", "row_id" => "i", "actual_reps" => 10, "actual_load_kg" => nil, "logged" => false, "interrupt" => true}
    ]

    facts =
      ExecutionAnalytics.completion_facts(
        %{started_at_utc: @now, completed_at_utc: @now, plan_sets: sets},
        []
      )

    assert %{
             plan_set_count: 3,
             plan_logged_set_count: 1,
             plan_interrupt_set_count: 1,
             plan_row_count: 2,
             plan_tonnage_kg: 1012.5
           } = facts

    refute Map.has_key?(ExecutionAnalytics.completion_facts(%{plan_sets: []}, []), :plan_set_count)
  end
end
