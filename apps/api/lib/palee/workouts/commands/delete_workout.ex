defmodule Palee.Workouts.Commands.DeleteWorkout do
  alias Palee.Workouts.WorkoutStore

  def call(id), do: WorkoutStore.delete_workout(id)
end
