defmodule Palee.Execution.Domain.ExecutionKpisTest do
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.ExecutionKpis

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

  describe "put_position/4" do
    test "records format, section and elapsed time, and the workout's formats once" do
      segments = [
        %{format: "tabata", section_name: "Tabata"},
        %{format: "amrap", section_name: "Finisher"}
      ]

      counters = ExecutionKpis.put_position(%{"pauses" => 1}, segments, 1, 90_000)

      assert counters["position"] == %{
               "format" => "amrap",
               "section_name" => "Finisher",
               "segment_index" => 1,
               "segment_count" => 2,
               "elapsed_ms" => 90_000
             }

      assert counters["formats"] == ["tabata", "amrap"]
      assert counters["pauses"] == 1
    end

    test "reports free-text workouts by their own format" do
      counters = ExecutionKpis.put_position(%{}, [], 0, 1_000)
      assert counters["position"]["format"] == "free_text"
      assert counters["formats"] == ["free_text"]
    end

    test "survives counter merges" do
      counters = ExecutionKpis.put_position(%{}, [], 0, 1_000)

      assert ExecutionKpis.merge_counters(counters, %{"pauses" => 1})["position"]["format"] ==
               "free_text"
    end
  end

  describe "summarize/1" do
    test "reports completion, abandon points, score capture and device counters" do
      executions = [
        %{
          status: :completed,
          source: :self_selected,
          current_segment_index: 5,
          total_elapsed_ms: 600_000,
          started_at_utc: ~U[2026-10-10 09:00:00Z],
          section_scores: [%{"source" => "manual", "value" => 10}],
          duration_adjustments: %{"segment:0" => %{"delta_seconds" => 60}},
          kpi_counters: %{
            "countdown_skips" => 1,
            "countdown_segments" => 8,
            "pauses" => 2,
            "paused_ms" => 60_000,
            "finish_wizard_opens" => 1,
            "first_start_delay_ms" => 20_000,
            "formats" => ["tabata", "amrap"]
          }
        },
        %{
          status: :completed,
          source: :assigned,
          current_segment_index: 3,
          total_elapsed_ms: 900_000,
          started_at_utc: ~U[2026-10-11 09:00:00Z],
          section_scores: [%{"source" => "auto", "value" => 4}],
          kpi_counters: %{
            "countdown_segments" => 2,
            "finish_wizard_opens" => 2,
            "formats" => ["emom"]
          }
        },
        %{
          status: :active,
          source: :self_selected,
          current_segment_index: 2,
          started_at_utc: ~U[2026-10-11 10:00:00Z],
          section_scores: [],
          kpi_counters: %{
            "formats" => ["emom"],
            "position" => %{"format" => "emom", "section_name" => "EMOM 10", "elapsed_ms" => 1}
          }
        },
        %{
          status: :paused,
          source: :self_selected,
          current_segment_index: 0,
          started_at_utc: ~U[2026-10-11 11:00:00Z],
          section_scores: [],
          kpi_counters: %{
            "formats" => ["free_text"],
            "position" => %{"format" => "free_text", "elapsed_ms" => 120_000}
          }
        }
      ]

      report = ExecutionKpis.summarize(executions)

      assert report.started == 4
      assert report.completed == 2
      assert report.completion_rate == 0.5
      assert report.score_capture_rate == 0.5
      assert report.skip_rate_on_countdowns == 0.1
      assert report.pauses_per_execution == 0.5
      assert report.average_paused_ms == 15_000
      assert report.median_time_to_first_start_ms == 20_000
      assert report.median_completed_duration_ms == 750_000
      assert report.clock_adjustment_rate == 0.25
      assert report.finish_wizard_drop_off_rate == 0.3333

      assert [%{format: "emom", count: 1, share: 0.5}, %{format: "free_text", count: 1}] =
               report.abandon_by_format

      assert %{format: "emom", section_name: "EMOM 10", segment_index: 2, count: 1} in report.abandon_points

      assert %{key: "emom", started: 2, completed: 1, completion_rate: 0.5} in report.by_format

      assert %{key: "self_selected", started: 3, completed: 1} =
               Enum.find(report.by_source, &(&1.key == "self_selected"))

      assert report.free_text == %{
               started: 1,
               completed: 0,
               completion_rate: 0.0,
               median_abandon_elapsed_ms: 120_000
             }

      assert report.structured == %{started: 3, completed: 2}

      assert report.daily == [
               %{date: "2026-10-10", started: 1, completed: 1},
               %{date: "2026-10-11", started: 3, completed: 1}
             ]
    end

    test "has no rates without data" do
      report = ExecutionKpis.summarize([])

      assert report.completion_rate == nil
      assert report.skip_rate_on_countdowns == nil
      assert report.finish_wizard_drop_off_rate == nil
      assert report.daily == []
    end
  end
end
