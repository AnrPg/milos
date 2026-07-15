defmodule MilosTraining.Execution.Domain.ProgressSnapshotterTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Execution.Domain.ProgressSnapshotter

  # Helper: build an EMOM segment for testing
  defp emom_segment(segment_key, section_id, scoring_mode, exercises, opts \\ []) do
    %{
      segment_key: segment_key,
      section_id: section_id,
      section_name: "EMOM",
      format: Keyword.get(opts, :format, "emom"),
      kind: :countdown,
      scoreable: true,
      score_config: nil,
      timer_config:
        Map.merge(
          %{
            type: Keyword.get(opts, :format, "emom"),
            duration_seconds: 600,
            interval_seconds: 60,
            scoring_mode: scoring_mode
          },
          Keyword.get(opts, :timer_config_extra, %{})
        ),
      exercises: exercises
    }
  end

  test "derives progress and final snapshots for for-time sections" do
    segments = [
      %{
        segment_key: "segment:0",
        section_id: "section-1",
        section_name: "Main Set",
        format: "for_time",
        kind: :countup,
        scoreable: true,
        score_config: %{type: "time", unit: "sec"},
        timer_config: %{},
        exercises: [
          %{id: "exercise-1", name: "Burpees", sets: 2, prescription_value: 10}
        ]
      }
    ]

    state = %{
      checked_exercise_ids: ["segment:0::exercise-1::set:1"],
      section_elapsed_ms: %{"section-1" => 125_000},
      segment_cycle_counts: %{}
    }

    assert [
             %{
               section_id: "section-1",
               value: 10,
               unit: "reps",
               score_type: "reps",
               kind: "progress"
             }
           ] = ProgressSnapshotter.progress_snapshots(segments, state)

    assert [
             %{
               section_id: "section-1",
               value: "2:05",
               score_type: "time",
               kind: "final"
             }
           ] = ProgressSnapshotter.final_snapshots(segments, state, [])
  end

  test "derives rounds plus reps for amrap sections with completed cycles" do
    segments = [
      %{
        segment_key: "segment:3",
        section_id: "section-amrap",
        section_name: "AMRAP",
        format: "amrap",
        kind: :countdown,
        scoreable: true,
        score_config: %{type: "rounds+reps"},
        timer_config: %{duration_seconds: 600},
        exercises: [
          %{id: "exercise-a", name: "Thrusters", prescription_value: 5},
          %{id: "exercise-b", name: "Pull Ups", prescription_value: 5}
        ]
      }
    ]

    state = %{
      checked_exercise_ids: ["segment:3::exercise-a"],
      section_elapsed_ms: %{"section-amrap" => 180_000},
      segment_cycle_counts: %{"segment:3" => 2}
    }

    assert [
             %{
               section_id: "section-amrap",
               value: "2 rounds + 5 reps",
               score_type: "rounds+reps",
               kind: "progress"
             }
           ] = ProgressSnapshotter.progress_snapshots(segments, state)

    assert [
             %{
               section_id: "section-amrap",
               value: "2 rounds + 5 reps",
               score_type: "rounds+reps",
               kind: "final"
             }
           ] = ProgressSnapshotter.final_snapshots(segments, state, [])
  end

  test "prefers manual final scores over auto-derived values" do
    segments = [
      %{
        segment_key: "segment:0",
        section_id: "section-1",
        section_name: "Main Set",
        format: "for_time",
        kind: :countup,
        scoreable: true,
        score_config: %{type: "time", unit: "sec"},
        timer_config: %{},
        exercises: [
          %{id: "exercise-1", name: "Burpees", sets: 2, prescription_value: 10}
        ]
      }
    ]

    state = %{
      checked_exercise_ids: ["segment:0::exercise-1::set:1", "segment:0::exercise-1::set:2"],
      section_elapsed_ms: %{"section-1" => 125_000},
      segment_cycle_counts: %{}
    }

    assert [
             %{
               section_id: "section-1",
               value: "1:59",
               score_type: "time",
               source: "manual",
               kind: "final"
             }
           ] =
             ProgressSnapshotter.final_snapshots(segments, state, [
               %{section_id: "section-1", value: "1:59", score_type: "time"}
             ])
  end

  describe "EMOM for_time mode" do
    test "progress: derives elapsed time from section_elapsed_ms" do
      segments = [
        emom_segment("seg:0", "sec-1", "for_time", []),
        emom_segment("seg:1", "sec-1", "for_time", [])
      ]

      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{"sec-1" => 75_000},
        segment_cycle_counts: %{}
      }

      assert [
               %{
                 section_id: "sec-1",
                 value: "1:15",
                 score_type: "accumulated_work_time",
                 kind: "progress"
               }
             ] =
               ProgressSnapshotter.progress_snapshots(segments, state)
    end

    test "final: derives accumulated_work_time" do
      segments = [emom_segment("seg:0", "sec-1", "for_time", [])]

      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{"sec-1" => 95_000},
        segment_cycle_counts: %{}
      }

      assert [
               %{
                 section_id: "sec-1",
                 value: "1:35",
                 score_type: "accumulated_work_time",
                 kind: "final"
               }
             ] =
               ProgressSnapshotter.final_snapshots(segments, state, [])
    end

    test "handles string-keyed timer_config (JSON-decoded segments)" do
      segments = [
        %{
          "format" => "emom",
          "timer_config" => %{"type" => "emom", "scoring_mode" => "for_time"},
          segment_key: "seg:0",
          section_id: "sec-str",
          section_name: "EMOM",
          format: "emom",
          kind: :countdown,
          scoreable: true,
          score_config: nil,
          timer_config: nil,
          exercises: []
        }
      ]

      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{"sec-str" => 60_000},
        segment_cycle_counts: %{}
      }

      assert [
               %{
                 section_id: "sec-str",
                 value: "1:00",
                 score_type: "accumulated_work_time",
                 kind: "progress"
               }
             ] =
               ProgressSnapshotter.progress_snapshots(segments, state)
    end
  end

  describe "EMOM for_quality mode" do
    test "progress: counts completed intervals" do
      segments = [
        emom_segment("seg:0", "sec-q", "for_quality", []),
        emom_segment("seg:1", "sec-q", "for_quality", [])
      ]

      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{},
        segment_cycle_counts: %{"seg:0" => 1}
      }

      assert [%{section_id: "sec-q", value: 1, unit: "intervals", kind: "progress"}] =
               ProgressSnapshotter.progress_snapshots(segments, state)
    end

    test "final: Pass when all intervals completed" do
      segments = [
        emom_segment("seg:0", "sec-q", "for_quality", []),
        emom_segment("seg:1", "sec-q", "for_quality", [])
      ]

      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{},
        segment_cycle_counts: %{"seg:0" => 1, "seg:1" => 1}
      }

      assert [%{section_id: "sec-q", value: "Pass", score_type: "pass_fail", kind: "final"}] =
               ProgressSnapshotter.final_snapshots(segments, state, [])
    end

    test "final: Fail when any interval not completed" do
      segments = [
        emom_segment("seg:0", "sec-q", "for_quality", []),
        emom_segment("seg:1", "sec-q", "for_quality", [])
      ]

      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{},
        segment_cycle_counts: %{"seg:0" => 1}
      }

      assert [%{section_id: "sec-q", value: "Fail", score_type: "pass_fail", kind: "final"}] =
               ProgressSnapshotter.final_snapshots(segments, state, [])
    end
  end

  describe "EMOM amrap mode" do
    test "progress and final: total cumulative reps across all windows" do
      ex = %{id: "ex-1", name: "Thrusters", sets: 1, prescription_value: 10}

      segments = [
        emom_segment("seg:0", "sec-a", "amrap", [ex]),
        emom_segment("seg:1", "sec-a", "amrap", [ex])
      ]

      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{},
        segment_cycle_counts: %{"seg:0" => 3, "seg:1" => 2}
      }

      assert [
               %{
                 section_id: "sec-a",
                 value: 50,
                 unit: "reps",
                 score_type: "reps",
                 kind: "progress"
               }
             ] =
               ProgressSnapshotter.progress_snapshots(segments, state)
    end
  end

  describe "EMOM to_failure mode" do
    test "progress and final: intervals survived = segments with cycle_count > 0" do
      segments = [
        emom_segment("seg:0", "sec-f", "to_failure", []),
        emom_segment("seg:1", "sec-f", "to_failure", []),
        emom_segment("seg:2", "sec-f", "to_failure", [])
      ]

      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{},
        segment_cycle_counts: %{"seg:0" => 1, "seg:1" => 1}
      }

      assert [
               %{
                 section_id: "sec-f",
                 value: 2,
                 unit: "intervals",
                 score_type: "intervals_survived",
                 kind: "progress"
               }
             ] =
               ProgressSnapshotter.progress_snapshots(segments, state)

      assert [
               %{
                 section_id: "sec-f",
                 value: 2,
                 unit: "intervals",
                 score_type: "intervals_survived",
                 kind: "final"
               }
             ] =
               ProgressSnapshotter.final_snapshots(segments, state, [])
    end
  end

  describe "Complex EMOM AMRAP lowest_window mode" do
    test "final: score is the lowest window rep count, not grand total" do
      ex = %{id: "ex-1", name: "Row", sets: 1, prescription_value: 5}

      segments = [
        emom_segment("seg:0", "sec-cx", "amrap", [ex],
          format: "complex_emom",
          timer_config_extra: %{amrap_scoring_style: "lowest_window"}
        ),
        emom_segment("seg:1", "sec-cx", "amrap", [ex],
          format: "complex_emom",
          timer_config_extra: %{amrap_scoring_style: "lowest_window"}
        ),
        emom_segment("seg:2", "sec-cx", "amrap", [ex],
          format: "complex_emom",
          timer_config_extra: %{amrap_scoring_style: "lowest_window"}
        )
      ]

      # seg:0 = 4 cycles → 20 reps, seg:1 = 2 cycles → 10 reps, seg:2 = 3 cycles → 15 reps
      # lowest_window = 10
      state = %{
        checked_exercise_ids: [],
        section_elapsed_ms: %{},
        segment_cycle_counts: %{"seg:0" => 4, "seg:1" => 2, "seg:2" => 3}
      }

      assert [%{section_id: "sec-cx", value: 10, unit: "reps", score_type: "reps", kind: "final"}] =
               ProgressSnapshotter.final_snapshots(segments, state, [])
    end
  end
end
