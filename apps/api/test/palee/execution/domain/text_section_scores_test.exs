defmodule Palee.Execution.Domain.TextSectionScoresTest do
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.{ProgressValidator, ScoreRanking, TextSectionScores, TimerPresets}

  @sections [
    %{
      id: "s1",
      name: "Strength",
      order: 1,
      section_metadata: %{"untitled" => false},
      timer_preset: %{"format" => "untimed"},
      score_config: %{
        "metrics" => [
          %{"key" => "top-set", "label" => "Top set", "kind" => "load", "unit" => "kg"}
        ]
      }
    },
    %{
      id: "s2",
      name: "2",
      order: 2,
      section_metadata: %{"untitled" => true},
      timer_preset: %{"format" => "amrap", "duration_seconds" => 600},
      score_config: %{
        "metrics" => [
          %{"key" => "rounds", "label" => "Rounds", "kind" => "rounds", "unit" => "rounds"},
          %{"key" => "time", "label" => "Time", "kind" => "time", "unit" => "s"}
        ]
      }
    }
  ]

  test "each result becomes a section score keyed by section and metric" do
    assert {:ok, [load, rounds]} =
             TextSectionScores.normalize(
               [
                 %{"section_id" => "s1", "metric_key" => "top-set", "value" => "102.5"},
                 %{"section_id" => "s2", "metric_key" => "rounds", "value" => 7},
                 %{"section_id" => "s2", "metric_key" => "time", "value" => ""}
               ],
               @sections
             )

    assert load == %{
             "section_id" => "s1",
             "section_key" => "s1:top-set",
             "section_name" => "Strength · Top set",
             "metric_key" => "top-set",
             "metric_label" => "Top set",
             "value" => 102.5,
             "unit" => "kg",
             "score_type" => "load",
             "source" => "user",
             "kind" => "final"
           }

    assert %{"section_name" => "#2 · Rounds", "value" => 7, "section_key" => "s2:rounds"} = rounds
  end

  test "unknown metrics, duplicates and non-numbers are refused" do
    assert TextSectionScores.normalize(nil, @sections) == {:ok, []}

    for entries <- [
          [%{section_id: "s1", metric_key: "rounds", value: 3}],
          [%{section_id: "nope", metric_key: "rounds", value: 3}],
          [%{section_id: "s2", metric_key: "rounds", value: -1}],
          [%{section_id: "s2", metric_key: "rounds", value: "seven"}],
          [
            %{section_id: "s2", metric_key: "rounds", value: 1},
            %{section_id: "s2", metric_key: "rounds", value: 2}
          ]
        ] do
      assert TextSectionScores.normalize(entries, @sections) == {:error, :bad_request}
    end

    assert TextSectionScores.normalize("x", @sections) == {:error, :bad_request}
  end

  test "an athlete may restart a text section's clock, so its time may go back" do
    segments = TimerPresets.build_sections(@sections)

    progress = %{
      checked_exercise_ids: [],
      current_segment_index: 0,
      paused_elapsed_ms: 0,
      total_elapsed_ms: 1_000,
      section_elapsed_ms: %{},
      segment_cycle_counts: %{}
    }

    assert ProgressValidator.validate(progress, segments, %{total_elapsed_ms: 60_000}) == :ok
  end

  test "a sectioned WOD ranks by the first score its coach set" do
    assert [first | _rest] =
             TextSectionScores.section_metrics(%{
               authoring_mode: "sectioned_text",
               sections: @sections
             })

    assert first == %{
             id: "s1",
             section_key: "s1:top-set",
             name: "Strength · Top set",
             score_type: "load",
             unit: "kg"
           }

    result = fn user, load ->
      {:ok, scores} =
        TextSectionScores.normalize(
          [%{section_id: "s1", metric_key: "top-set", value: load}],
          @sections
        )

      %{user_id: user, section_scores: scores}
    end

    assert [%{user_id: "b", rank: 1}, %{user_id: "a", rank: 2}] =
             ScoreRanking.rank([result.("a", 90), result.("b", 100)], first)
  end
end
