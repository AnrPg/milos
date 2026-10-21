defmodule Palee.Execution.Domain.TimerSequenceBuilderTest do
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.TimerSequenceBuilder

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

  test "emom to_failure mode: one open-ended interval cycle capped at max_windows" do
    s =
      section(%{
        type: "emom",
        duration_seconds: 300,
        interval_seconds: 60,
        scoring_mode: "to_failure",
        max_windows: 20
      })

    assert [segment] = TimerSequenceBuilder.build(workout([s]))
    assert segment.kind == :interval_cycle
    assert segment.duration_seconds == 60
    assert segment.total_rounds == 20
  end

  test "emom to_failure mode: without max_windows the cycle has no cap" do
    s =
      section(%{
        type: "emom",
        interval_seconds: 60,
        scoring_mode: "to_failure"
      })

    assert [%{kind: :interval_cycle, total_rounds: nil}] =
             TimerSequenceBuilder.build(workout([s]))
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

  test "complex_emom to_failure mode: uses max_windows as the window cap" do
    s =
      section(%{
        type: "complex_emom",
        duration_seconds: 600,
        interval_seconds: 60,
        scoring_mode: "to_failure",
        max_windows: 15
      })

    assert [%{kind: :interval_cycle, duration_seconds: 60, total_rounds: 15}] =
             TimerSequenceBuilder.build(workout([s]))
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

  defp exercise(id, attrs \\ %{}),
    do: Map.merge(%{id: id, item_type: "exercise", name: id}, attrs)

  defp labels(segments), do: Enum.map(segments, & &1.label)

  describe "complex EMOM rotation" do
    test "assigned exercises keep rotating after the first cycle" do
      exercises = for n <- 1..3, do: exercise("ex-#{n}", %{interval_assignment: n})

      segments =
        %{type: "complex_emom", duration_seconds: 360, interval_seconds: 60}
        |> section(exercises)
        |> then(&workout([&1]))
        |> TimerSequenceBuilder.build()

      assert Enum.map(segments, fn segment -> Enum.map(segment.exercises, & &1.id) end) ==
               [["ex-1"], ["ex-2"], ["ex-3"], ["ex-1"], ["ex-2"], ["ex-3"]]
    end

    test "an interval pattern sets each window's length and the rotation length" do
      exercises = [
        exercise("bike", %{interval_assignment: 1}),
        exercise("rower", %{interval_assignment: 2}),
        exercise("plank")
      ]

      segments =
        %{
          type: "complex_emom",
          duration_seconds: 330,
          interval_seconds: 60,
          interval_pattern_seconds: [60, 120]
        }
        |> section(exercises)
        |> then(&workout([&1]))
        |> TimerSequenceBuilder.build()

      # 60 + 120 + 60 + 90 (final window clamped to the remaining time)
      assert Enum.map(segments, & &1.duration_seconds) == [60, 120, 60, 90]

      assert Enum.map(segments, fn segment -> Enum.map(segment.exercises, & &1.id) end) ==
               [["bike", "plank"], ["rower", "plank"], ["bike", "plank"], ["rower", "plank"]]
    end
  end

  describe "rounds, rests and caps" do
    test "for time with rounds keeps one capped count-up that tracks the round target" do
      assert [segment] =
               %{type: "for_time", rounds: 5, time_cap_seconds: 720}
               |> section()
               |> then(&workout([&1]))
               |> TimerSequenceBuilder.build()

      assert %{kind: :countup, duration_seconds: 720, total_rounds: 5} = segment
    end

    test "train to exhaustion emits timed sets with rest between them" do
      segments =
        %{type: "train_to_exhaustion", rounds: 3, rest_seconds: 90}
        |> section([exercise("push-up")])
        |> then(&workout([&1]))
        |> TimerSequenceBuilder.build()

      assert labels(segments) == ["Set 1/3", "Rest", "Set 2/3", "Rest", "Set 3/3"]

      assert Enum.map(segments, & &1.kind) == [
               :countup,
               :countdown,
               :countup,
               :countdown,
               :countup
             ]

      assert Enum.map(segments, & &1.phase) == ~w(work rest work rest work)
    end

    test "death by is an open-ended EMOM capped by ladder_cap" do
      assert [segment] =
               %{type: "death_by", start_reps: 1, step_reps: 1, ladder_cap: 20}
               |> section([exercise("thruster")])
               |> then(&workout([&1]))
               |> TimerSequenceBuilder.build()

      assert %{kind: :interval_cycle, duration_seconds: 60, total_rounds: 20} = segment
    end

    test "ladders and pyramids run a capped stopwatch" do
      for type <- ~w(ladder_ascending ladder_descending pyramid) do
        assert [%{kind: :countup, duration_seconds: 600}] =
                 %{
                   type: type,
                   start_reps: 1,
                   step_reps: 1,
                   min_reps: 1,
                   peak_reps: 5,
                   time_cap_seconds: 600
                 }
                 |> section([exercise("burpee")])
                 |> then(&workout([&1]))
                 |> TimerSequenceBuilder.build()
      end
    end

    test "interval formats do not end with a rest" do
      for type <- ~w(tabata custom_hiit billat) do
        segments =
          %{type: type, work_seconds: 20, rest_seconds: 10, rounds: 3, cycles: 3}
          |> section([exercise("bike")])
          |> then(&workout([&1]))
          |> TimerSequenceBuilder.build()

        assert length(segments) == 5
        assert List.last(segments).phase == "work"
      end
    end

    test "untimed sections with authored rounds get one segment per round and rests" do
      segments =
        %{type: "untimed"}
        |> section([exercise("pull-up")])
        |> Map.put(:section_metadata, %{"rounds" => 3, "rest_between_rounds_seconds" => 60})
        |> then(&workout([&1]))
        |> TimerSequenceBuilder.build()

      assert labels(segments) == ["Round 1/3", "Rest", "Round 2/3", "Rest", "Round 3/3"]
    end

    test "cluster sets split into clusters with intra rest and full rest between sets" do
      segments =
        %{type: "cluster", sets: 2, intra_rest_seconds: 15, cluster_reps: 2, rest_seconds: 120}
        |> section([exercise("clean")])
        |> then(&workout([&1]))
        |> TimerSequenceBuilder.build()

      assert Enum.map(segments, &{&1.kind, &1.duration_seconds}) == [
               {:manual, nil},
               {:countdown, 15},
               {:manual, nil},
               {:countdown, 120},
               {:manual, nil},
               {:countdown, 15},
               {:manual, nil}
             ]
    end

    test "hrr recovers on a stopwatch capped by recovery_cap_seconds" do
      [effort, recovery] =
        %{type: "hrr", effort_seconds: 60, hr_drop_target: 20, recovery_cap_seconds: 180}
        |> section([exercise("assault bike")])
        |> then(&workout([&1]))
        |> TimerSequenceBuilder.build()

      assert %{kind: :countdown, duration_seconds: 60, phase: "work"} = effort

      assert %{kind: :countup, duration_seconds: 180, phase: "rest", label: "Recover −20 bpm"} =
               recovery
    end

    test "zero-length countdowns are skipped" do
      [segment] =
        %{type: "hrr", effort_seconds: 0, rest_seconds: 60}
        |> section([exercise("bike")])
        |> then(&workout([&1]))
        |> TimerSequenceBuilder.build()

      assert segment.duration_seconds == 60
    end
  end

  describe "between sections" do
    defp timed(id, order, extra) do
      %{type: "amrap", duration_seconds: 300}
      |> section([exercise("#{id}-ex")])
      |> Map.merge(%{id: id, order: order})
      |> Map.merge(extra)
    end

    test "inserts transitions and rests between sections, never at the edges" do
      segments =
        TimerSequenceBuilder.build(
          workout([
            timed("a", 1, %{
              section_metadata: %{"transition_seconds" => 30},
              rest_before_next_section_seconds: 120
            }),
            timed("b", 2, %{section_metadata: %{"transition_seconds" => 15}}),
            timed("c", 3, %{rest_before_next_section_seconds: 90})
          ])
        )

      assert Enum.map(segments, &{&1.section_id, &1.duration_seconds}) == [
               {"a", 300},
               {"a:rest-after", 120},
               {"b:transition", 15},
               {"b", 300},
               {"c", 300}
             ]

      between = Enum.filter(segments, &Map.get(&1, :between_sections))
      assert Enum.all?(between, &(&1.scoreable == false and &1.exercises == []))
    end
  end

  describe "localizable labels" do
    test "segments carry a label key and parameters next to the English label" do
      workout = %{
        sections: [
          %{
            id: "tabata",
            name: "Tabata",
            order: 1,
            timer_config: %{type: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 2},
            exercises: []
          }
        ]
      }

      segments = TimerSequenceBuilder.build(workout)

      assert Enum.map(segments, &{&1.label, &1.label_key, &1.label_params}) == [
               {"Work 1/2", "work", %{round: 1, total: 2}},
               {"Rest 1/2", "rest_round", %{round: 1, total: 2}},
               {"Work 2/2", "work", %{round: 2, total: 2}}
             ]
    end

    test "segments named after their section have no label key" do
      workout = %{
        sections: [
          %{
            id: "a",
            name: "AMRAP 12",
            order: 1,
            timer_config: %{type: "amrap", duration_seconds: 720}
          }
        ]
      }

      assert [%{label: "AMRAP 12", label_key: nil, label_params: %{}}] =
               TimerSequenceBuilder.build(workout)
    end
  end
end
