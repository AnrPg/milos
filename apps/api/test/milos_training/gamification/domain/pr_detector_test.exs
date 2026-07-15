defmodule MilosTraining.Gamification.Domain.PRDetectorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.PRDetector

  test "detects a PR when a lower time beats the previous best" do
    history = [%{section_id: "s1", value: 300, score_type: :time}]
    new_score = %{section_id: "s1", value: 250, score_type: :time}

    assert PRDetector.is_pr?(new_score, history)
  end

  test "does not flag a worse reps score as a PR" do
    history = [%{section_id: "s1", value: 12, score_type: :reps}]
    new_score = %{section_id: "s1", value: 10, score_type: :reps}

    refute PRDetector.is_pr?(new_score, history)
  end

  test "parses mm:ss values for time-based scores" do
    history = [%{section_id: "s1", value: "05:10", score_type: :time}]
    new_score = %{section_id: "s1", value: "04:55", score_type: :time}

    assert PRDetector.is_pr?(new_score, history)
  end

  test "parses rounds and reps formats" do
    history = [%{section_id: "s1", value: "4 rounds + 3 reps", score_type: :"rounds+reps"}]
    new_score = %{section_id: "s1", value: "5 rounds + 1 reps", score_type: :"rounds+reps"}

    assert PRDetector.is_pr?(new_score, history)
  end

  test "parses load values with units" do
    history = [%{section_id: "s1", value: "80 kg", score_type: :load}]
    new_score = %{section_id: "s1", value: "82.5 kg", score_type: :load}

    assert PRDetector.is_pr?(new_score, history)
  end
end
