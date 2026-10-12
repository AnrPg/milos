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
    timeline =
      ProgressStats.pr_timeline([
        entry("squat", "Back squat", 115.0, "2026-10-01"),
        entry("squat", "Back squat", 100.0, "2026-08-01"),
        entry("dead", "Deadlift", 150.0, "2026-09-10")
      ])

    assert [
             %{name: "Back squat", score: 115.0, previous_score: 100.0, change: 15.0},
             %{name: "Deadlift", previous_score: nil, change: nil},
             %{name: "Back squat", score: 100.0, previous_score: nil}
           ] = timeline
  end
end
