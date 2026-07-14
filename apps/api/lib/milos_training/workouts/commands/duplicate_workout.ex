defmodule MilosTraining.Workouts.Commands.DuplicateWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id, title_suffix \\ "(copy)"), do: WorkoutStore.duplicate_workout(id, title_suffix)
end
