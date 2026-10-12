defmodule MilosTraining.Workouts.Domain.WorkoutAssistant.ContractTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.WorkoutAssistant.Contract

  @source "AMRAP 12\n10 pul ups\nBack squat 5x5 @ 100kg"

  defp valid do
    %{
      "workout" => %{"title" => "AMRAP day", "type" => "crossfit"},
      "sections" => [
        %{
          "name" => "Metcon",
          "format" => "amrap",
          "timer" => [%{"key" => "duration_seconds", "value" => "720"}],
          "exercises" => [%{"name" => "pul ups", "reps" => 10, "bodyweight" => true}]
        },
        %{
          "name" => "Strength",
          "format" => "untimed",
          "timer" => [],
          "exercises" => [%{"name" => "Back squat", "sets" => 5, "reps" => 5, "load_kg" => 100}]
        }
      ],
      "issues" => [
        %{
          "path" => "sections.0.exercises.0.name",
          "severity" => "warning",
          "message" => "Misspelled.",
          "suggested_value" => "pull ups",
          "find_text" => "pul ups",
          "replace_text" => "pull ups"
        }
      ],
      "missing_fields" => [
        %{"path" => "workout.difficulty", "reason" => "x", "suggested_value" => "intermediate"}
      ]
    }
  end

  defp problems(raw), do: raw |> Contract.check(@source) |> Enum.map(&{&1["path"], &1["problem"]})

  test "a correct answer has no violations" do
    assert Contract.check(valid(), @source) == []
  end

  test "requires the top-level arrays and rejects unknown keys" do
    raw = valid() |> Map.delete("issues") |> Map.put("comment", "hi")
    paths = Enum.map(problems(raw), &elem(&1, 0))
    assert "issues" in paths
    assert "comment" in paths
  end

  test "checks timer keys against the section format" do
    raw =
      put_in(valid(), ["sections", Access.at(0), "format"], "emom")

    assert [{"sections.0.timer", problem}] = problems(raw)
    assert problem =~ "interval_seconds"

    raw =
      put_in(valid(), ["sections", Access.at(0), "timer"], [
        %{"key" => "rounds", "value" => "3"},
        %{"key" => "duration_seconds", "value" => "720"}
      ])

    assert [{"sections.0.timer.0", problem}] = problems(raw)
    assert problem =~ "not valid for amrap"

    raw = put_in(valid(), ["sections", Access.at(0), "format"], "spin class")
    assert [{"sections.0.format", _}] = problems(raw)
  end

  test "allows one prescription and one load per exercise" do
    raw =
      update_in(
        valid(),
        ["sections", Access.at(1), "exercises", Access.at(0)],
        &Map.merge(&1, %{"duration_seconds" => 30, "bodyweight" => true})
      )

    assert length(problems(raw)) == 2
  end

  test "find_text must be verbatim and the fix must be actionable and consistent" do
    raw = put_in(valid(), ["issues", Access.at(0), "find_text"], "pull ups please")
    assert [{"issues.0.find_text", _}] = problems(raw)

    raw =
      update_in(
        valid(),
        ["issues", Access.at(0)],
        &Map.drop(&1, ["suggested_value", "find_text", "replace_text"])
      )

    assert [{"issues.0", problem}] = problems(raw)
    assert problem =~ "warning needs"

    raw = put_in(valid(), ["issues", Access.at(0), "suggested_value"], "Pull-up")
    assert [{"issues.0.suggested_value", _}] = problems(raw)
  end

  test "issue paths must point at existing fields" do
    raw = put_in(valid(), ["issues", Access.at(0), "path"], "sections.7.exercises.0.name")
    assert [{"issues.0.path", _}] = problems(raw)
  end

  test "rejects non-objects" do
    assert [%{"problem" => "the answer must be one JSON object"}] = Contract.check([], @source)
  end
end
