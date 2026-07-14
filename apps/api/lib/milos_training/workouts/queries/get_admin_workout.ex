defmodule MilosTraining.Workouts.Queries.GetAdminWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def by_id(id), do: WorkoutStore.get_workout_for_admin(id)
end
