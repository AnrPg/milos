defmodule Palee.Workouts.Commands.ReopenWorkout do
  alias Palee.Workouts.WorkoutStore

  def call(id), do: WorkoutStore.reopen_workout(id)
end
