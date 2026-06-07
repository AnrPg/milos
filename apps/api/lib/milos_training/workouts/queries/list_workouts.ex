defmodule MilosTraining.Workouts.Queries.ListWorkouts do
  alias MilosTraining.Workouts.WorkoutStore

  def all, do: WorkoutStore.list_workouts()
end
