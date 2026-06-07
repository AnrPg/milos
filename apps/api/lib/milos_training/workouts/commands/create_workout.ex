defmodule MilosTraining.Workouts.Commands.CreateWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(admin_id, params), do: WorkoutStore.create_workout(admin_id, params)
end
