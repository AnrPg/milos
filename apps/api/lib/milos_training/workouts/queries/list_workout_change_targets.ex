defmodule MilosTraining.Workouts.Queries.ListWorkoutChangeTargets do
  alias MilosTraining.Workouts.WorkoutStore

  def for_workout(workout_id), do: WorkoutStore.list_workout_change_targets(workout_id)
end
