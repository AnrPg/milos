defmodule MilosTraining.Workouts.Commands.DeleteAssignedWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id), do: WorkoutStore.delete_assigned_workout(id)
end
