defmodule Palee.Workouts.Queries.GetWorkout do
  alias Palee.Workouts.Queries.PlanPrescriptions
  alias Palee.Workouts.WorkoutStore

  # ADR-270: a plan section is scored as its plan says (`PlanPrescriptions`).
  def by_id(context, id), do: context |> WorkoutStore.get_workout(id) |> PlanPrescriptions.decorate()
end
