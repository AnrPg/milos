defmodule Palee.Workouts.Domain.WorkoutAssistant.IssueAnchorTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.WorkoutAssistant.IssueAnchor

  @source "Strength\nBack Squat 5x5 @ 75%\n\nMetcon\n21-15-9 thrustrs and pull-ups"
  @workout %{
    "title" => "Friday",
    "sections" => [
      %{"name" => "Strength", "exercises" => [%{"name" => "back squat"}]},
      %{"name" => "Metcon", "exercises" => [%{"name" => "Thruster"}, %{"name" => "Pull-up"}]}
    ]
  }

  test "a text fix is anchored on the words it replaces" do
    issue = %{"path" => "text", "suggestion" => %{"text_edit" => %{"find" => "thrustrs"}}}
    assert IssueAnchor.find(issue, @workout, nil, @source) == "thrustrs"
  end

  test "the assistant's quote, then the exercise or section the path points at, as written" do
    assert IssueAnchor.find(%{"path" => "sections.0.exercises.0.load_value"}, @workout, "5x5 @ 75%", @source) ==
             "5x5 @ 75%"

    assert IssueAnchor.find(%{"path" => "sections.0.exercises.0.sets"}, @workout, "not there", @source) ==
             "Back Squat"

    assert IssueAnchor.find(%{"path" => "sections.1.timer_config"}, @workout, nil, @source) == "Metcon"
  end

  test "nothing to mark when the words are not in the text" do
    assert IssueAnchor.find(%{"path" => "title"}, @workout, nil, @source) == nil
    assert IssueAnchor.find(%{"path" => "sections.1.exercises.0.name"}, @workout, nil, @source) == "Metcon"
  end
end
