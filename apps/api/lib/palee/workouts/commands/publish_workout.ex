defmodule Palee.Workouts.Commands.PublishWorkout do
  alias Palee.Workouts.WorkoutStore

  def call(id, params), do: WorkoutStore.publish_workout(id, params)
end
