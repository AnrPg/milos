defmodule Palee.Workouts.Domain.SectionScoringTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.SectionScoring

  test "a section without scoring stays unscored" do
    assert SectionScoring.normalize(nil) == {:ok, nil}
    assert SectionScoring.normalize(%{"metrics" => []}) == {:ok, nil}
  end

  test "metrics are keyed by the coach's name, with the kind's unit" do
    assert {:ok, %{"metrics" => [thrusters, pull_ups, time]}} =
             SectionScoring.normalize(%{
               metrics: [
                 %{label: " Thrusters ", kind: "reps"},
                 %{"label" => "Pull-ups", "kind" => "reps"},
                 %{label: "Χρόνος", kind: "time"}
               ]
             })

    assert thrusters == %{
             "key" => "thrusters",
             "label" => "Thrusters",
             "kind" => "reps",
             "unit" => "reps"
           }

    assert pull_ups["key"] == "pull-ups"
    assert time == %{"key" => "χρόνος", "label" => "Χρόνος", "kind" => "time", "unit" => "s"}
  end

  test "a custom metric has no unit; unknown kinds, blank or duplicate names are refused" do
    assert {:ok, %{"metrics" => [%{"kind" => "custom", "unit" => nil}]}} =
             SectionScoring.normalize([%{label: "Burpees over bar"}])

    assert SectionScoring.normalize([%{label: "x", kind: "vibes"}]) == {:error, :scoring_invalid}
    assert SectionScoring.normalize([%{label: "  ", kind: "reps"}]) == {:error, :scoring_invalid}

    assert SectionScoring.normalize([
             %{label: "Reps", kind: "reps"},
             %{label: "reps", kind: "reps"}
           ]) ==
             {:error, :scoring_invalid}

    too_many = for i <- 1..7, do: %{label: "M#{i}", kind: "reps"}
    assert SectionScoring.normalize(too_many) == {:error, :scoring_invalid}
  end
end
