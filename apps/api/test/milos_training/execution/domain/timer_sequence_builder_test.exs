defmodule MilosTraining.Execution.Domain.TimerSequenceBuilderTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Execution.Domain.TimerSequenceBuilder

  defp section(timer_config, exercises \\ []) do
    %{
      id: "section-1",
      name: "Main Set",
      order: 1,
      parent_section_id: nil,
      scoreable: true,
      score_config: nil,
      timer_config: timer_config,
      exercises: exercises
    }
  end

  defp workout(sections), do: %{sections: sections}

  test "emom AMRAP mode: generates ceil(duration/interval) segments" do
    s =
      section(%{
        type: "emom",
        duration_seconds: 300,
        interval_seconds: 60,
        scoring_mode: "amrap"
      })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 5
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
    assert Enum.all?(segments, &(&1.kind == :countdown))
  end

  test "emom to_failure mode: generates max_windows segments each at full interval" do
    s =
      section(%{
        type: "emom",
        duration_seconds: 300,
        interval_seconds: 60,
        scoring_mode: "to_failure",
        max_windows: 20
      })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 20
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
  end

  test "emom to_failure mode: defaults to 100 max_windows when not specified" do
    s =
      section(%{
        type: "emom",
        duration_seconds: 0,
        interval_seconds: 60,
        scoring_mode: "to_failure"
      })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 100
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
  end

  test "emom for_time mode: generates same segment count as amrap" do
    s =
      section(%{
        type: "emom",
        duration_seconds: 600,
        interval_seconds: 60,
        scoring_mode: "for_time"
      })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 10
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
  end

  test "emom for_quality mode: generates same segment count as amrap" do
    s =
      section(%{
        type: "emom",
        duration_seconds: 600,
        interval_seconds: 60,
        scoring_mode: "for_quality"
      })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 10
  end

  test "complex_emom to_failure mode: uses max_windows rounds" do
    s =
      section(%{
        type: "complex_emom",
        duration_seconds: 600,
        interval_seconds: 60,
        scoring_mode: "to_failure",
        max_windows: 15
      })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 15
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
  end

  test "emom to_failure mode: max_windows 0 produces no segments" do
    s =
      section(%{
        type: "emom",
        duration_seconds: 0,
        interval_seconds: 60,
        scoring_mode: "to_failure",
        max_windows: 0
      })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert segments == []
  end

  test "emom labels each segment Min N" do
    s =
      section(%{
        type: "emom",
        duration_seconds: 180,
        interval_seconds: 60
      })

    segments = TimerSequenceBuilder.build(workout([s]))
    labels = Enum.map(segments, & &1.label)
    assert labels == ["Min 1", "Min 2", "Min 3"]
  end

  test "preserves section notes and authored header rows for presentation" do
    header = %{id: "header-1", item_type: "header", name: "Primary lifts", note: "Header note"}
    exercise = %{id: "exercise-1", item_type: "exercise", name: "Back squat", note: "Brace"}

    [segment] =
      workout([
        section(%{type: "for_time"}, [header, exercise])
        |> Map.put(:note, "Section note")
      ])
      |> TimerSequenceBuilder.build()

    assert segment.section_note == "Section note"
    assert Enum.map(segment.exercises, & &1.item_type) == ["header", "exercise"]
    assert Enum.map(segment.exercises, & &1.note) == ["Header note", "Brace"]
  end

  test "flattens draft-shaped nested sections and assigns stable synthetic parent ids" do
    nested = %{
      name: "Nested AMRAP",
      order: 1,
      timer_config: %{type: "amrap", duration_seconds: 300},
      exercises: [%{name: "Burpee", item_type: "exercise"}]
    }

    parent =
      section(%{type: "untimed"}, [])
      |> Map.delete(:id)
      |> Map.put(:sections, [nested])

    [child_segment] = TimerSequenceBuilder.build(workout([parent]))
    assert child_segment.section_name == "Nested AMRAP"
    assert child_segment.kind == :countdown
    assert child_segment.duration_seconds == 300
  end

  test "conditional recovery without a duration becomes a manual segment" do
    [segment] =
      section(%{type: "rest", recovery_condition: "heart rate below 120"})
      |> then(&workout([&1]))
      |> TimerSequenceBuilder.build()

    assert segment.kind == :manual
    assert segment.duration_seconds == nil
  end
end
