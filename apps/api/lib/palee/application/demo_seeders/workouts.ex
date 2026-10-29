defmodule Palee.Application.DemoSeeders.Workouts do
  @moduledoc """
  ADR-184: a few library workouts for the workouts screen, written as the
  owner through `Workouts.create_workout/3` (drafts, never published or
  assigned, so no one is notified).

  ADR-270: two of them are written in the structured WOD editor
  (`structured_plan`), so a demo shows what plans can say: a superset done
  set-wise with values that change per set, rounds of two kinds with values
  that change per round (and keep stepping after the written ones), and an
  interruption every few minutes.
  """

  @behaviour Palee.Application.DemoSeeder

  alias Palee.Workouts

  @workouts [
    {"Fran (demo)", :crossfit, [{"Thrusters", 21, "reps"}, {"Pull-ups", 21, "reps"}]},
    {"Back squat 5x5 (demo)", :strength, [{"Back squat", 5, "reps"}]},
    {"Engine builder (demo)", :crossfit,
     [{"Row", 500, "meters"}, {"Burpees", 15, "reps"}, {"Air squats", 20, "reps"}]}
  ]

  @impl true
  def section, do: "workouts"

  @impl true
  def requires, do: []

  @impl true
  def sources, do: ["master_workouts"]

  @impl true
  def seed(context, _seeded, _now) do
    workouts =
      Enum.map(@workouts, fn {title, type, exercises} -> params(title, type, exercises) end) ++
        plan_workouts()

    Enum.reduce_while(workouts, {:ok, []}, fn params, {:ok, rows} ->
      case Workouts.create_workout(context, context.account, params) do
        {:ok, workout} -> {:cont, {:ok, rows ++ [{"master_workouts", workout.id}]}}
        error -> {:halt, error}
      end
    end)
  end

  @doc "The structured plan demo workouts (ADR-270), as `create_workout` params."
  def plan_workouts do
    [
      %{
        title: "Strength supersets (demo)",
        type: :strength,
        authoring_mode: "structured_plan",
        sections: [
          plan_section("Back squat", 1, %{
            "flow" => "sets",
            "params" => %{"sets" => "4", "rest" => "2:00"},
            "score" => "best_load",
            "blocks" => [
              [
                plan_row("demo-sq", "Back Squat", %{
                  "note" => "Control the descent",
                  "extra" => ["tempo"],
                  "cells" => [
                    %{"d" => "8", "l" => "60kg", "tempo" => "31X1"},
                    %{"d" => "6", "l" => "+5"},
                    %{"d" => "5", "l" => ""},
                    %{"d" => "8-10", "l" => "60kg"}
                  ]
                })
              ]
            ]
          }),
          plan_section("Upper superset", 2, %{
            "flow" => "sets",
            "params" => %{"sets" => "3", "rest" => "90″"},
            "score" => "none",
            "blocks" => [
              [
                plan_row("demo-bp", "Dumbbell Bench Press", %{
                  "group" => "demo-ss",
                  "cells" => [%{"d" => "12", "l" => "20kg"}, %{"d" => "10", "l" => "22.5kg"}]
                }),
                plan_row("demo-pu", "Pull-up", %{
                  "group" => "demo-ss",
                  "cells" => [%{"d" => "8-10", "l" => ""}]
                }),
                plan_row("demo-lunge", "Walking Lunge", %{
                  "group" => "demo-ss",
                  "extra" => ["side"],
                  "cells" => [%{"d" => "10", "l" => "16kg"}]
                })
              ]
            ]
          })
        ]
      },
      %{
        title: "Engine with interruptions (demo)",
        type: :crossfit,
        authoring_mode: "structured_plan",
        sections: [
          plan_section("Climbing AMRAP", 1, %{
            "flow" => "amrap",
            "params" => %{"dur" => "12", "intEvery" => "3:00"},
            "mods" => %{"interrupt" => true},
            "preset" => "interrupt",
            "score" => "rounds_reps",
            "blocks" => [
              [
                plan_row("demo-pc", "Power Clean", %{
                  "perRound" => true,
                  "cells" => [%{"d" => "5", "l" => "40kg"}, %{"d" => "5", "l" => "+5kg"}]
                }),
                plan_row("demo-tb", "Toes to Bar", %{"dose" => "10"})
              ],
              [
                plan_row("demo-row", "Row", %{"dose" => "15 cal"}),
                plan_row("demo-wb", "Wall Ball", %{"dose" => "15", "load" => "9kg"})
              ]
            ],
            "interrupt" => [plan_row("demo-burpee", "Burpee", %{"dose" => "5"})]
          })
        ]
      }
    ]
  end

  defp plan_section(name, order, plan) do
    %{name: name, order: order, exercises: [], plan: Map.put(plan, "v", 1)}
  end

  defp plan_row(id, name, more) do
    Map.merge(
      %{"id" => id, "kind" => "ex", "name" => name, "dose" => "", "load" => "", "cells" => []},
      more
    )
  end

  defp params(title, type, exercises) do
    %{
      title: title,
      type: type,
      sections: [
        %{
          name: "Main Set",
          order: 1,
          scoreable: false,
          exercises:
            exercises
            |> Enum.with_index(1)
            |> Enum.map(fn {{name, value, unit}, order} ->
              %{
                name: name,
                order: order,
                sets: 3,
                prescription_value: value,
                prescription_unit: unit
              }
            end)
        }
      ]
    }
  end
end
