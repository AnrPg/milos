defmodule MilosTraining.Workouts.Queries.ListAdminWorkouts do
  alias MilosTraining.Workouts.WorkoutStore

  def all, do: WorkoutStore.list_workouts()
end
