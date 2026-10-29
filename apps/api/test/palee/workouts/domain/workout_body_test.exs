defmodule Palee.Workouts.Domain.WorkoutBodyTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.WorkoutBody

  test "a structured workout keeps its exercises and lists count them" do
    workout = %{
      authoring_mode: "structured",
      sections: [
        %{
          id: "s1",
          name: "Main",
          timer_config: %{"type" => "amrap"},
          scoreable: true,
          exercises: [
            %{name: "Squat", item_type: "exercise"},
            %{name: "Row", item_type: "exercise"}
          ]
        }
      ]
    }

    assert %{kind: "structured", sections: [%{name: "Main", scoreable: true, exercises: [_, _]}]} =
             WorkoutBody.build(workout)

    assert %{kind: "structured", sections: [%{name: "Main", exercise_count: 2}]} =
             WorkoutBody.summary(workout)
  end

  test "free text says whether the assistant derived exercises and lists cut long text" do
    long = String.duplicate("x", 400)

    workout = %{
      "authoring_mode" => "free_text",
      "free_text_body" => long,
      "workout_metadata" => %{"free_text_timer" => %{"format" => "amrap"}},
      "sections" => [%{"name" => "A", "exercises" => [%{"item_type" => "header"}]}]
    }

    assert %{kind: "free_text", structured: false, timer: %{"format" => "amrap"}} =
             WorkoutBody.build(workout)

    assert %{kind: "free_text", excerpt: excerpt} = WorkoutBody.summary(workout)
    assert String.length(excerpt) == 280
  end

  test "an untitled text section has no title; scoring metrics are kept" do
    workout = %{
      authoring_mode: "sectioned_text",
      sections: [
        %{
          name: "1",
          section_metadata: %{"untitled" => true},
          free_text_body: "21-15-9",
          timer_preset: %{"format" => "for_time"},
          score_config: %{"metrics" => [%{"key" => "time", "label" => "Time"}]}
        }
      ]
    }

    assert %{
             kind: "text_sections",
             sections: [%{title: nil, text: "21-15-9", scoring: [%{"key" => "time"}]}]
           } = WorkoutBody.build(workout)

    assert %{sections: [%{scored: true, excerpt: "21-15-9"}]} = WorkoutBody.summary(workout)
  end

  test "ADR-270: a structured plan carries its plans; lists name each section's flow and count" do
    plan = Palee.StructuredPlanFixtures.program() |> Enum.at(8)

    workout = %{
      authoring_mode: "structured_plan",
      sections: [
        %{id: "s1", name: "Engine", plan: plan, exercises: [%{name: "Row"}]},
        %{"id" => "s2", "name" => "Rest", "plan" => nil}
      ]
    }

    assert %{
             kind: "plan",
             sections: [
               %{
                 id: "s1",
                 name: "Engine",
                 plan: ^plan,
                 prescription: %{clock: %{flow: "for_time"}, rows: [_, _, _, _]}
               },
               %{id: "s2", name: "Rest", plan: nil, prescription: nil}
             ]
           } = WorkoutBody.build(workout)

    assert WorkoutBody.summary(workout) == %{
             kind: "plan",
             sections: [
               %{name: "Engine", flow: "for_time", exercise_count: 4},
               %{name: "Rest", flow: nil, exercise_count: 0}
             ]
           }

    assert WorkoutBody.kind("structured_plan") == "plan"
    assert "plan" in WorkoutBody.kinds()
  end
end
