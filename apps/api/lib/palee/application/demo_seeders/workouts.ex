defmodule Palee.Application.DemoSeeders.Workouts do
  @moduledoc """
  ADR-184: a few library workouts for the workouts screen, written as the
  owner through `Workouts.create_workout/3` (drafts, never published or
  assigned, so no one is notified).
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
    Enum.reduce_while(@workouts, {:ok, []}, fn {title, type, exercises}, {:ok, rows} ->
      case Workouts.create_workout(context, context.account, params(title, type, exercises)) do
        {:ok, workout} -> {:cont, {:ok, rows ++ [{"master_workouts", workout.id}]}}
        error -> {:halt, error}
      end
    end)
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
