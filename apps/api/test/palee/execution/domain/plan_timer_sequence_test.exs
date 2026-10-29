defmodule Palee.Execution.Domain.PlanTimerSequenceTest do
  @moduledoc """
  ADR-270: a structured plan workout runs on its plan's clock and is scored as
  its plan says, so the completion the plan runner sends (its section scores
  and section times) is accepted.
  """
  use ExUnit.Case, async: true

  import Palee.StructuredPlanFixtures

  alias Palee.Execution.Domain.{ProgressSnapshotter, ProgressValidator, TimerSequenceBuilder}
  alias Palee.Workouts.Domain.StructuredPlan.Prescription
  alias Palee.Workouts.Queries.PlanPrescriptions

  # The workout read model of a plan workout, as `Workouts.get_workout/2` returns it.
  defp workout(plans) do
    %{
      authoring_mode: "structured_plan",
      sections:
        plans
        |> Enum.with_index(1)
        |> Enum.map(fn {plan, order} ->
          %{
            id: "s#{order}",
            name: "Section #{order}",
            order: order,
            parent_section_id: nil,
            scoreable: false,
            score_config: nil,
            timer_config: nil,
            plan: plan,
            prescription: plan |> Prescription.build() |> Prescription.to_json(),
            exercises: [%{id: "e#{order}", name: "Ex #{order}", sets: 1}]
          }
        end)
    }
    |> PlanPrescriptions.decorate()
  end

  defp segments(index), do: TimerSequenceBuilder.build(workout([Enum.at(program(), index)]))

  test "each flow runs on its own clock" do
    # sets: 4 sets with 2:00 rests, untimed work.
    sets = segments(0)

    assert Enum.map(sets, & &1.kind) == [
             :no_timer,
             :countdown,
             :no_timer,
             :countdown,
             :no_timer,
             :countdown,
             :no_timer
           ]

    assert Enum.all?(sets, &(&1.format == "structured_plan"))
    assert %{label_key: "set", label_params: %{set: 1, total: 4}} = hd(sets)

    assert Enum.at(sets, 1) |> Map.take([:phase, :duration_seconds]) == %{
             phase: "rest",
             duration_seconds: 120
           }

    # EMOM 4 × 2:30.
    assert [%{kind: :interval_cycle, duration_seconds: 150, total_rounds: 4}] = segments(4)

    # AMRAP 7'.
    assert [%{kind: :countdown, duration_seconds: 420, scoreable: true}] = segments(6)

    # For Time, 4 rounds, cap 20'.
    assert [%{kind: :countup, duration_seconds: 1200, total_rounds: 4}] = segments(8)

    # AMRAP windows 3-3-3-4 with a minute between them.
    windows = segments(9)
    assert Enum.map(windows, & &1.duration_seconds) == [180, 60, 180, 60, 180, 60, 240]
    assert Enum.map(windows, & &1.phase) == ~w(work rest work rest work rest work)

    # Intervals with heart-rate rests: a manual recovery between work bouts.
    intervals = segments(10)
    assert length(intervals) == 15
    assert %{kind: :countdown, duration_seconds: 20} = hd(intervals)
    assert %{kind: :manual, label_key: "recover", phase: "rest"} = Enum.at(intervals, 1)

    # Rest.
    assert [%{kind: :countdown, duration_seconds: 120, phase: "rest", scoreable: false}] =
             segments(11)
  end

  test "the preview totals the timed part and says when it is open-ended" do
    preview = TimerSequenceBuilder.preview(workout([Enum.at(program(), 5)]))
    assert %{total_seconds: 480, open_ended: false} = preview

    assert %{open_ended: true} = TimerSequenceBuilder.preview(workout([Enum.at(program(), 0)]))
  end

  test "the plan runner's completion is accepted: its scores and its section times" do
    plans = [Enum.at(program(), 6), Enum.at(program(), 7), Enum.at(program(), 0)]
    segments = TimerSequenceBuilder.build(workout(plans))

    scores = [
      %{section_id: "s1", value: "5+3", score_type: "rounds_reps"},
      %{section_id: "s2", value: "7:45", score_type: "time"}
    ]

    assert :ok = ProgressSnapshotter.validate_manual_scores(segments, scores)

    # A score of another type than the plan's is refused; a section scored
    # "none" takes no score.
    assert {:error, :bad_request} =
             ProgressSnapshotter.validate_manual_scores(segments, [
               %{section_id: "s1", value: 300, score_type: "time"}
             ])

    assert {:error, :bad_request} =
             ProgressSnapshotter.validate_manual_scores(segments, [
               %{section_id: "s3", value: 100, score_type: "load"}
             ])

    assert :ok =
             ProgressValidator.validate(
               %{
                 checked_exercise_ids: [],
                 current_segment_index: 0,
                 paused_elapsed_ms: 0,
                 total_elapsed_ms: 1_200_000,
                 section_elapsed_ms: %{"s1" => 420_000, "s2" => 465_000, "s3" => 315_000},
                 segment_cycle_counts: %{}
               },
               segments,
               %{}
             )

    final =
      ProgressSnapshotter.final_snapshots(
        segments,
        %{section_elapsed_ms: %{"s2" => 465_000}},
        scores
      )

    assert %{"s1" => "5+3", "s2" => "7:45"} = Map.new(final, &{&1.section_id, &1.value})
  end

  test "a workout that is not a plan keeps its own segments" do
    workout = %{
      sections: [
        %{
          id: "a",
          name: "AMRAP",
          order: 1,
          parent_section_id: nil,
          timer_config: %{type: "amrap", duration_seconds: 600},
          exercises: []
        }
      ]
    }

    assert [%{format: "amrap", kind: :countdown, duration_seconds: 600}] =
             TimerSequenceBuilder.build(workout)
  end
end
