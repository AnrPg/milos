defmodule MilosTraining.Workouts.Queries.GetWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def by_id(id), do: WorkoutStore.get_workout(id)
end
