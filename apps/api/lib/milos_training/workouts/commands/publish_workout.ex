defmodule MilosTraining.Workouts.Commands.PublishWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id, params), do: WorkoutStore.publish_workout(id, params)
end
