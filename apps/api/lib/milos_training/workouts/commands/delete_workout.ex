defmodule MilosTraining.Workouts.Commands.DeleteWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id), do: WorkoutStore.delete_workout(id)
end
