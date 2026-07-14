defmodule MilosTraining.Workouts.Commands.ReopenWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id), do: WorkoutStore.reopen_workout(id)
end
