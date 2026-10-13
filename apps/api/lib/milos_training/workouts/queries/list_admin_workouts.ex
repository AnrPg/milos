defmodule MilosTraining.Workouts.Queries.ListAdminWorkouts do
  alias MilosTraining.Workouts.WorkoutStore

  def all(context), do: WorkoutStore.list_workouts(context)
end
