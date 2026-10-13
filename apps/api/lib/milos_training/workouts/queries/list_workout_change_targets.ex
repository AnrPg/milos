defmodule MilosTraining.Workouts.Queries.ListWorkoutChangeTargets do
  alias MilosTraining.Workouts.WorkoutStore

  def for_workout(context, workout_id),
    do: WorkoutStore.list_workout_change_targets(context, workout_id)
end
