defmodule Palee.Workouts.Commands.DeleteAssignedWorkout do
  alias Palee.Workouts.WorkoutStore

  def call(id), do: WorkoutStore.delete_assigned_workout(id)
end
