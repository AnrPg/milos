defmodule MilosTraining.Execution.Domain.ProgressValidatorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Execution.Domain.ProgressValidator

  @segments [
    %{
      segment_key: "segment:0",
      section_id: "section-1",
      exercises: [%{id: "exercise-1", sets: 2, excluded: false}]
    }
  ]

  test "accepts progress that belongs to the materialized sequence" do
    assert :ok =
             ProgressValidator.validate(
               %{
                 checked_exercise_ids: ["segment:0::exercise-1::set:1"],
                 current_segment_index: 0,
                 paused_elapsed_ms: 100,
                 total_elapsed_ms: 100,
                 section_elapsed_ms: %{"section-1" => 100},
                 segment_cycle_counts: %{"segment:0" => 1}
               },
               @segments,
               %{total_elapsed_ms: 0, section_elapsed_ms: %{}, segment_cycle_counts: %{}}
             )
  end

  test "rejects forged identifiers, keys, indexes, oversized values, and regressions" do
    invalid_states = [
      %{checked_exercise_ids: ["forged"], current_segment_index: 0},
      %{checked_exercise_ids: [], current_segment_index: 1},
      %{checked_exercise_ids: [], current_segment_index: 0, section_elapsed_ms: %{"x" => 1}},
      %{checked_exercise_ids: [], current_segment_index: 0, segment_cycle_counts: %{"x" => 1}},
      %{checked_exercise_ids: [], current_segment_index: 0, total_elapsed_ms: 2_592_000_001},
      %{checked_exercise_ids: [], current_segment_index: 0, total_elapsed_ms: 9}
    ]

    for state <- invalid_states do
      progress =
        Map.merge(
          %{
            checked_exercise_ids: [],
            current_segment_index: 0,
            paused_elapsed_ms: 0,
            total_elapsed_ms: 10,
            section_elapsed_ms: %{},
            segment_cycle_counts: %{}
          },
          state
        )

      assert {:error, :bad_request} =
               ProgressValidator.validate(progress, @segments, %{
                 total_elapsed_ms: 10,
                 section_elapsed_ms: %{},
                 segment_cycle_counts: %{}
               })
    end
  end

  test "accepts a lower round count so an accidental +1 round can be undone" do
    progress = %{
      checked_exercise_ids: [],
      current_segment_index: 0,
      paused_elapsed_ms: 0,
      total_elapsed_ms: 10,
      section_elapsed_ms: %{},
      segment_cycle_counts: %{"segment:0" => 1}
    }

    assert :ok =
             ProgressValidator.validate(progress, @segments, %{
               total_elapsed_ms: 10,
               section_elapsed_ms: %{},
               segment_cycle_counts: %{"segment:0" => 2}
             })
  end

  test "lets a free-text clock (no timer segments) be reset, but not a structured one" do
    progress = %{
      checked_exercise_ids: [],
      current_segment_index: 0,
      paused_elapsed_ms: 0,
      total_elapsed_ms: 5,
      section_elapsed_ms: %{},
      segment_cycle_counts: %{}
    }

    previous = %{total_elapsed_ms: 60_000, section_elapsed_ms: %{}}

    assert :ok = ProgressValidator.validate(progress, [], previous)
    assert {:error, :bad_request} = ProgressValidator.validate(progress, @segments, previous)
  end
end
