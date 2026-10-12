defmodule MilosTraining.Workouts.Domain.WorkoutAssistant.ProofreadingTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.WorkoutAssistant.Proofreading

  @source "3 rnds\n10 pul ups\ncap 12"

  test "keeps only verbatim, non-overlapping corrections" do
    raw = %{
      "corrections" => [
        %{
          "find_text" => "pul ups",
          "replace_text" => "pull-ups",
          "kind" => "spelling",
          "message" => "Typo",
          "label" => "Use pull-ups"
        },
        %{"find_text" => "10 pul", "replace_text" => "10 pull", "kind" => "spelling"},
        %{"find_text" => "not in text", "replace_text" => "x"},
        %{"find_text" => "cap 12", "replace_text" => "cap 12", "kind" => "unit"},
        %{"find_text" => "rnds", "replace_text" => "rounds", "kind" => "weird"}
      ]
    }

    corrections = Proofreading.verify(raw, @source)
    assert Enum.map(corrections, & &1["find"]) == ["rnds", "10 pul"]
    assert Enum.find(corrections, &(&1["find"] == "rnds"))["kind"] == "spelling"
  end

  test "maps corrections onto canonical fields when the field holds the words" do
    workout = %{
      "title" => "Day",
      "sections" => [%{"name" => "Main", "note" => nil, "exercises" => [%{"name" => "pul ups"}]}]
    }

    [field_issue, text_issue] =
      Proofreading.to_issues(
        [
          %{
            "find" => "pul ups",
            "replace" => "pull-ups",
            "kind" => "spelling",
            "message" => "Typo",
            "label" => "Fix"
          },
          %{
            "find" => "cap 12",
            "replace" => "cap 12 min",
            "kind" => "unit",
            "message" => "Unit",
            "label" => "Add min"
          }
        ],
        workout
      )

    assert field_issue["path"] == "sections.0.exercises.0.name"
    assert field_issue["suggestion"]["value"] == "pull-ups"
    assert field_issue["code"] == "text_correction"
    assert text_issue["path"] == "text"
    assert text_issue["suggestion"]["value"] == nil

    assert text_issue["suggestion"]["text_edit"] == %{
             "find" => "cap 12",
             "replace" => "cap 12 min"
           }
  end

  test "garbage input yields no corrections" do
    assert Proofreading.verify(%{"corrections" => "nope"}, @source) == []
    assert Proofreading.verify(nil, @source) == []
  end
end
