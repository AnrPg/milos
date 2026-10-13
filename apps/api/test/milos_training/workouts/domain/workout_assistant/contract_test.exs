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

  test "checks timer keys against the section format's schema" do
    raw =
      put_in(valid(), ["sections", Access.at(0), "format"], "emom")

    assert [{"sections.0.timer.interval_seconds", problem}] = problems(raw)
    assert problem =~ "is required for emom"

    raw =
      put_in(valid(), ["sections", Access.at(0), "timer"], [
        %{"key" => "rounds", "value" => "3"},
        %{"key" => "duration_seconds", "value" => "720"}
      ])

    assert [{"sections.0.timer.rounds", problem}] = problems(raw)
    assert problem =~ "not part of the amrap schema"

    raw = put_in(valid(), ["sections", Access.at(0), "format"], "spin class")
    assert [{"sections.0.format", _}] = problems(raw)

    raw = update_in(valid(), ["sections", Access.at(0)], &Map.delete(&1, "format"))
    assert [{"sections.0.format", problem}] = problems(raw)
    assert problem =~ "infer"
  end

  test "accepts the canonical object timer and format aliases" do
    raw =
      valid()
      |> put_in(["sections", Access.at(0), "timer"], %{"duration_seconds" => 720})
      |> put_in(["sections", Access.at(1), "format"], "circuit")

    assert problems(raw) == []

    raw = put_in(valid(), ["sections", Access.at(0), "timer"], %{"duration_seconds" => "720"})
    assert [{"sections.0.timer.duration_seconds", "must be integer"}] = problems(raw)
  end

  test "enforces each format's exercise structure" do
    complex = %{
      "name" => "Rotating EMOM",
      "format" => "complex_emom",
      "timer" => %{"duration_seconds" => 720, "interval_seconds" => 60},
      "exercises" => [
        %{"name" => "Row", "calories" => 12, "interval_assignment" => 1},
        %{"name" => "Burpee", "reps" => 10}
      ]
    }

    raw = put_in(valid(), ["sections"], [complex])
    assert [{"sections.0.exercises.1.interval_assignment", "is required"}] = problems(raw)

    raw =
      put_in(valid(), ["sections"], [
        put_in(complex, ["exercises", Access.at(1), "interval_assignment"], 3)
      ])

    assert [{"sections.0.exercises", problem}] = problems(raw)
    assert problem =~ "without gaps"

    ladder = %{
      "name" => "21-15-9",
      "format" => "ladder_descending",
      "timer" => %{"start_reps" => 21, "step_reps" => 6, "min_reps" => 9},
      "exercises" => [%{"name" => "Thruster", "reps" => 21, "load_kg" => 43}]
    }

    raw = put_in(valid(), ["sections"], [ladder])
    assert [{"sections.0.exercises.0.reps", problem}] = problems(raw)
    assert problem =~ "ladder"

    raw =
      put_in(valid(), ["sections"], [
        %{
          "name" => "Rest",
          "format" => "rest",
          "score" => "time",
          "exercises" => [%{"name" => "Walk"}]
        }
      ])

    paths = Enum.map(problems(raw), &elem(&1, 0))
    assert "sections.0.score" in paths
    assert "sections.0.exercises" in paths
  end

  test "a workout can chain sections of different formats" do
    raw =
      put_in(valid(), ["sections"], [
        %{
          "name" => "Warm-up",
          "format" => "untimed",
          "exercises" => [%{"name" => "Air squat", "reps" => 20}]
        },
        %{
          "name" => "EMOM",
          "format" => "emom",
          "timer" => %{"duration_seconds" => 600, "interval_seconds" => 60},
          "score" => "rounds",
          "exercises" => [%{"name" => "Power clean", "reps" => 3, "load_percent_1rm" => 70}]
        },
        %{
          "name" => "Tabata",
          "format" => "tabata",
          "timer" => %{"work_seconds" => 20, "rest_seconds" => 10, "rounds" => 8},
          "exercises" => [%{"name" => "Air squat"}]
        },
        %{
          "name" => "Rest",
          "format" => "rest",
          "timer" => %{"duration_seconds" => 120},
          "exercises" => []
        },
        %{
          "name" => "Finisher",
          "format" => "ladder_descending",
          "timer" => %{"start_reps" => 21, "step_reps" => 6, "min_reps" => 9},
          "score" => "time",
          "exercises" => [%{"name" => "Thruster", "load_kg" => 43}, %{"name" => "Pull-up"}]
        }
      ])
      |> Map.put("issues", [])

    assert problems(raw) == []
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

  test "assumptions must explain a real field, timer keys included" do
    raw =
      valid()
      |> put_in(["sections", Access.at(0), "timer"], %{"duration_seconds" => 720})
      |> Map.put("assumptions", [
        %{"path" => "sections.0.timer.duration_seconds", "message" => "AMRAP 12 is 12 minutes."},
        %{"path" => "sections.0.exercises.0.name", "message" => "Read pul ups as pull-ups."}
      ])

    assert problems(raw) == []

    raw =
      Map.put(valid(), "assumptions", [
        %{"path" => "sections.0.timer.interval_seconds", "message" => "x"},
        %{"path" => "sections.0.name"}
      ])

    assert [{"assumptions.0.path", _}, {"assumptions.1.message", _}] = problems(raw)
    assert [{"assumptions", _}] = problems(Map.put(valid(), "assumptions", "none"))
  end
end
