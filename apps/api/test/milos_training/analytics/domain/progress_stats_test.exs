defmodule MilosTraining.Analytics.Domain.ProgressStatsTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Analytics.Domain.ProgressStats

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
end
