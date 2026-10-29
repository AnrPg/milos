defmodule Palee.Analytics.Domain.ProgressStatsTest do
  use ExUnit.Case, async: true

  alias Palee.Analytics.Domain.ProgressStats

  defp entry(record, name, score, on),
    do: %{
      id: "#{record}-#{on}",
      pr_record_id: record,
      name: name,
      unit: "kg",
      higher_is_better: true,
      score: score,
      beaten_on: on,
      inserted_at: "#{on}T10:00:00Z"
    }

  test "the PR timeline lists improvements newest first with the score they beat" do
    # History keeps superseded scores; the current one is on the record.
    records = [
      %{
        id: "squat",
        name: "Back squat",
        unit: "kg",
        higher_is_better: true,
        current_score: 115.0,
        beaten_on: "2026-10-01",
        updated_at: "2026-10-01T10:00:00Z"
      },
      %{
        id: "dead",
        name: "Deadlift",
        unit: "kg",
        higher_is_better: true,
        current_score: 150.0,
        beaten_on: "2026-09-10",
        updated_at: "2026-09-10T10:00:00Z"
      }
    ]

    timeline =
      ProgressStats.pr_timeline([entry("squat", "Back squat", 100.0, "2026-08-01")], records)

    assert [
             %{name: "Back squat", score: 115.0, previous_score: 100.0, change: 15.0},
             %{name: "Deadlift", previous_score: nil, change: nil},
             %{name: "Back squat", score: 100.0, previous_score: nil}
           ] = timeline
  end

  defp session(id, at),
    do: %{
      id: id,
      status: "completed",
      completed_at_utc: at,
      master_workout_id: "w",
      total_elapsed_ms: 600_000
    }

  test "the weekly span follows the given weeks and days lists each day with training" do
    # 2026-10-22 is a Thursday; the 4-week span starts Monday 2026-09-28.
    today = ~D[2026-10-22]

    stats =
      ProgressStats.build(
        [
          session("a", ~U[2026-10-21 08:00:00Z]),
          session("b", ~U[2026-10-21 18:00:00Z]),
          session("c", ~U[2026-10-05 08:00:00Z]),
          session("d", ~U[2026-09-01 08:00:00Z]),
          %{session("e", ~U[2026-10-20 08:00:00Z]) | status: "abandoned"}
        ],
        today,
        4
      )

    assert Enum.map(stats.weekly, & &1.week_start) ==
             [~D[2026-09-28], ~D[2026-10-05], ~D[2026-10-12], ~D[2026-10-19]]

    assert stats.days == [
             %{date: ~D[2026-10-05], sessions: 1},
             %{date: ~D[2026-10-21], sessions: 2}
           ]

    assert %{weeks: 4, active_weeks: 2, percent: 50, current_streak_weeks: 1} = stats.consistency
    assert %{weeks: 12} = ProgressStats.build([], today).consistency
  end

  test "the range sets the weeks; all spans from the first session, bounded" do
    alias Palee.Analytics.Domain.ProgressFilter

    today = ~D[2026-10-22]

    weeks = fn range, first ->
      ProgressFilter.weeks(%ProgressFilter{range: range}, today, first)
    end

    assert weeks.("4w", nil) == 4
    assert weeks.("6m", nil) == 26
    assert weeks.("1y", nil) == 52
    assert weeks.("all", nil) == 12
    assert weeks.("all", ~D[2026-10-01]) == 12
    assert weeks.("all", ~D[2026-01-05]) == 42
    assert weeks.("all", ~D[2020-01-01]) == 156
  end

  test "plan workouts add their lifted volume and the heaviest set of each exercise per session" do
    lift = fn id, at, kg, top_sets ->
      id
      |> session(at)
      |> Map.put(:plan_workload, %{volume_kg: kg, top_sets: top_sets})
    end

    squat = fn kg -> %{name: "Back Squat", exercise_ref: "back_squat", load_kg: kg, reps: 5} end
    snatch = %{name: "Power Snatch", exercise_ref: nil, load_kg: 50, reps: 3}

    stats =
      ProgressStats.build(
        [
          lift.("a", ~U[2026-10-20 10:00:00Z], 2530, [squat.(100)]),
          lift.("b", ~U[2026-10-27 10:00:00Z], 1200.5, [squat.(105), snatch]),
          session("c", ~U[2026-10-28 10:00:00Z])
        ],
        ~D[2026-10-29],
        2
      )

    assert stats.totals.volume_kg == 3730.5
    assert Enum.map(stats.weekly, & &1.volume_kg) == [2530, 1200.5]

    # The snatch was lifted once: no history yet.
    assert [%{name: "Back Squat", exercise_ref: "back_squat", points: points}] =
             stats.exercise_loads

    assert Enum.map(points, &{&1.execution_id, &1.load_kg}) == [{"a", 100}, {"b", 105}]
  end
end
