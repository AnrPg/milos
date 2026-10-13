defmodule MilosTraining.Workouts.Queries.GetWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def by_id(context, id), do: WorkoutStore.get_workout(context, id)
end
