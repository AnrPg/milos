defmodule MilosTraining.Workouts.Domain.FreeTextAnalysisTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.FreeTextAnalysis

  @source """
  Murph prep
  For time, cap 20 min:
  5 rounds
  10 pull ups
  20 push ups @ bw
  Back squat 5x5 @ 100kgs
  """

  defp raw(overrides \\ %{}) do
    Map.merge(
      %{
        "workout" => %{
          "title" => "Murph prep",
          "type" => "CrossFit",
          "difficulty" => "Intermediate",
          "estimated_duration_minutes" => 25,
          "equipment" => ["pull-up bar", "barbell", "barbell"],
          "tags" => []
        },
        "sections" => [
          %{
            "name" => "Main",
            "format" => "for_time",
            "timer" => [
              %{"key" => "rounds", "value" => "5"},
              %{"key" => "time_cap_seconds", "value" => "1200"},
              %{"key" => "unknown_key", "value" => "1"}
            ],
            "exercises" => [
              %{"name" => "Pull-up", "reps" => 10},
              %{"name" => "Push-up", "reps" => "20", "bodyweight" => true},
              %{"name" => "Back squat", "sets" => 5, "reps" => 5, "load_kg" => "100"}
            ]
          }
        ],
        "issues" => [],
        "missing_fields" => []
      },
      overrides
    )
  end

  test "maps the assistant reading onto the canonical workout shape" do
    %{"workout" => workout, "issues" => issues, "summary" => summary} =
      FreeTextAnalysis.normalize(raw(), @source)

    assert workout["title"] == "Murph prep"
    assert workout["type"] == "crossfit"
    assert workout["difficulty"] == "intermediate"
    assert workout["estimated_duration_seconds"] == 1500
    assert workout["equipment"] == ["pull-up bar", "barbell"]

    [section] = workout["sections"]

    assert section["timer_config"] == %{
             "type" => "for_time",
             "rounds" => 5,
             "time_cap_seconds" => 1200
           }

    [pull_up, push_up, squat] = section["exercises"]
    assert pull_up["prescription_value"] == 10
    assert pull_up["prescription_unit"] == "reps"
    assert push_up["load_mode"] == "bw"
    assert squat["sets"] == 5
    assert squat["load_value"] == 100
    assert squat["load_mode"] == "absolute"

    assert issues == []
    assert summary["exercises"] == 3
    assert summary["blocking"] == 0
  end

  test "flags missing required fields as blocking errors" do
    result =
      raw(%{"workout" => %{"type" => "spinning"}})
      |> put_in(["sections", Access.at(0), "exercises"], [%{"reps" => 3}])
      |> FreeTextAnalysis.normalize(@source)

    by_path = Map.new(result["issues"], &{&1["path"], &1})

    assert %{"code" => "missing_title", "required" => true, "severity" => "error"} =
             by_path["title"]

    assert %{"code" => "missing_type", "required" => true} = by_path["type"]
    assert by_path["type"]["current_value"] == "spinning"

    assert %{"code" => "missing_exercise_name", "required" => true} =
             by_path["sections.0.exercises.0.name"]

    assert result["summary"]["blocking"] == 3
  end

  test "drops invalid optional values and reports them without blocking" do
    result =
      raw()
      |> put_in(["workout", "difficulty"], "insane")
      |> put_in(["sections", Access.at(0), "exercises", Access.at(0), "sets"], "lots")
      |> FreeTextAnalysis.normalize(@source)

    assert result["workout"]["difficulty"] == nil
    assert Enum.at(hd(result["workout"]["sections"])["exercises"], 0)["sets"] == nil

    paths = Enum.map(result["issues"], & &1["path"])
    assert "difficulty" in paths
    assert "sections.0.exercises.0.sets" in paths
    assert Enum.all?(result["issues"], &(&1["required"] == false))
    assert result["summary"]["blocking"] == 0
  end

  test "reports timers missing required fields instead of persisting them" do
    result =
      raw()
      |> put_in(["sections", Access.at(0), "format"], "emom")
      |> put_in(["sections", Access.at(0), "timer"], [
        %{"key" => "duration_seconds", "value" => 600}
      ])
      |> FreeTextAnalysis.normalize(@source)

    assert hd(result["workout"]["sections"])["timer_config"] == nil

    assert [%{"code" => "invalid_timer", "params" => %{"missing" => ["interval_seconds"]}}] =
             result["issues"]
  end

  test "keeps assistant issues only for known paths and verbatim text edits" do
    issues = [
      %{
        "path" => "sections[0].exercises[2].load_kg",
        "severity" => "warning",
        "message" => "“kgs” looks like a typo.",
        "suggestion_label" => "Use kg",
        "suggested_value" => "100",
        "find_text" => "100kgs",
        "replace_text" => "100 kg"
      },
      %{"path" => "workout.color", "message" => "unknown field"},
      %{
        "path" => "title",
        "message" => "Title could be clearer",
        "find_text" => "not in the text",
        "replace_text" => "Murph"
      }
    ]

    result = FreeTextAnalysis.normalize(raw(%{"issues" => issues}), @source)

    assert [load_issue] = result["issues"]
    assert load_issue["path"] == "sections.0.exercises.2.load_value"
    assert load_issue["code"] == "assistant"
    assert load_issue["suggestion"]["value"] == 100
    assert load_issue["suggestion"]["text_edit"] == %{"find" => "100kgs", "replace" => "100 kg"}
    assert load_issue["id"] == "issue-1"
  end

  test "suggests only missing fields with valid values plus recommended workout fields" do
    missing = [
      %{
        "path" => "sections.0.exercises.0.rest_seconds",
        "suggested_value" => "60",
        "reason" => "Pacing"
      },
      %{"path" => "difficulty", "suggested_value" => "advanced"},
      %{"path" => "workout.estimated_duration_minutes", "suggested_value" => "45"},
      %{"path" => "sections.0.exercises.1.tempo", "suggested_value" => ""}
    ]

    result =
      raw(%{"missing_fields" => missing})
      |> put_in(["workout", "tags"], ["hero"])
      |> put_in(["workout", "estimated_duration_minutes"], nil)
      |> FreeTextAnalysis.normalize(@source)

    by_path = Map.new(result["suggestions"], &{&1["path"], &1})

    assert by_path["sections.0.exercises.0.rest_seconds"]["value"] == 60
    refute Map.has_key?(by_path, "difficulty")
    assert by_path["estimated_duration_seconds"]["value"] == 2700
    refute Map.has_key?(by_path, "sections.0.exercises.1.tempo")
    assert %{"value" => nil} = by_path["description"]
  end

  test "tolerates garbage input" do
    result = FreeTextAnalysis.normalize(%{"sections" => "nope", "workout" => 3}, "")

    assert result["workout"]["sections"] == []
    assert Enum.any?(result["issues"], &(&1["path"] == "title"))
    assert FreeTextAnalysis.normalize(nil, "")["summary"]["blocking"] == 2
  end

  test "coerce/2 validates values per canonical path" do
    assert {:ok, "all-levels"} = FreeTextAnalysis.coerce("difficulty", "All levels")
    assert {:ok, 90} = FreeTextAnalysis.coerce("sections.1.exercises.0.rest_seconds", "90")
    assert :error = FreeTextAnalysis.coerce("sections.1.exercises.0.sets", 0)
    assert :error = FreeTextAnalysis.coerce("nonsense", "x")
    assert FreeTextAnalysis.required_path?("sections.3.exercises.1.name")
    refute FreeTextAnalysis.required_path?("sections.3.exercises.1.tempo")
  end

  test "reads the canonical object timer, the section score and interval slots" do
    raw = %{
      "workout" => %{"title" => "Rotating EMOM", "type" => "crossfit"},
      "sections" => [
        %{
          "name" => "EMOM",
          "format" => "complex_emom",
          "timer" => %{"duration_seconds" => 720, "interval_seconds" => 60},
          "score" => "rounds",
          "exercises" => [
            %{"name" => "Row", "calories" => 12, "interval_assignment" => 1},
            %{"name" => "Burpee", "reps" => 10, "interval_assignment" => 2}
          ]
        },
        %{
          "name" => "Rest",
          "format" => "rest",
          "timer" => %{"duration_seconds" => 120},
          "score" => "time",
          "exercises" => []
        }
      ]
    }

    %{"workout" => %{"sections" => [emom, rest]}} = FreeTextAnalysis.normalize(raw, "EMOM")

    assert emom["timer_config"] == %{
             "type" => "complex_emom",
             "duration_seconds" => 720,
             "interval_seconds" => 60
           }

    assert emom["scoreable"] == true
    assert emom["score_config"] == %{"type" => "rounds"}
    assert Enum.map(emom["exercises"], & &1["interval_assignment"]) == [1, 2]

    # A score the format does not allow is dropped.
    refute Map.has_key?(rest, "scoreable")
  end
end
