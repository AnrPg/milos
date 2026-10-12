defmodule MilosTraining.Execution.Domain.ExecutionKpisTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Execution.Domain.ExecutionKpis

  @started ~U[2026-10-12 10:00:00.000000Z]

  describe "merge_counters/3" do
    test "keeps the larger value per counter and drops unknown keys" do
      merged =
        ExecutionKpis.merge_counters(
          %{"pauses" => 3, "skips" => 1},
          %{"pauses" => 2, "skips" => 4, "hacked" => 99, "paused_ms" => -5},
          @started
        )

      assert merged == %{"pauses" => 3, "skips" => 4}
    end

    test "records time to first start once, relative to the execution start" do
      first_start = DateTime.to_unix(@started, :millisecond) + 42_000

      merged =
        ExecutionKpis.merge_counters(%{}, %{"first_started_at_ms" => first_start}, @started)

      assert merged["first_start_delay_ms"] == 42_000

      later =
        ExecutionKpis.merge_counters(
          merged,
          %{first_started_at_ms: first_start + 60_000},
          @started
        )

      assert later["first_start_delay_ms"] == 42_000
    end

    test "ignores implausible device clocks and missing payloads" do
      too_early = DateTime.to_unix(@started, :millisecond) - 1

      assert ExecutionKpis.merge_counters(%{}, %{"first_started_at_ms" => too_early}, @started) ==
               %{}

      assert ExecutionKpis.merge_counters(%{"pauses" => 1}, nil, @started) == %{"pauses" => 1}
    end
  end

  describe "summarize/1" do
    test "reports completion, abandon points, score capture and device counters" do
      executions = [
        %{
          status: :completed,
          current_segment_index: 5,
          section_scores: [%{"source" => "manual", "value" => 10}],
          kpi_counters: %{
            "countdown_skips" => 1,
            "countdown_segments" => 8,
            "pauses" => 2,
            "paused_ms" => 60_000,
            "finish_wizard_opens" => 1,
            "first_start_delay_ms" => 20_000
          }
        },
        %{
          status: :completed,
          current_segment_index: 3,
          section_scores: [%{"source" => "auto", "value" => 4}],
          kpi_counters: %{"countdown_segments" => 2, "finish_wizard_opens" => 2}
        },
        %{status: :active, current_segment_index: 2, section_scores: [], kpi_counters: %{}},
        %{status: :paused, current_segment_index: 2, section_scores: [], kpi_counters: %{}}
      ]

      report = ExecutionKpis.summarize(executions)

      assert report.started == 4
      assert report.completed == 2
      assert report.completion_rate == 0.5
      assert report.abandon_points == [%{segment_index: 2, count: 2}]
      assert report.score_capture_rate == 0.5
      assert report.skip_rate_on_countdowns == 0.1
      assert report.pauses_per_execution == 0.5
      assert report.average_paused_ms == 15_000
      assert report.median_time_to_first_start_ms == 20_000
      assert report.finish_wizard_drop_off_rate == 0.3333
    end

    test "has no rates without data" do
      report = ExecutionKpis.summarize([])

      assert report.completion_rate == nil
      assert report.skip_rate_on_countdowns == nil
      assert report.finish_wizard_drop_off_rate == nil
    end
  end
end
