defmodule MilosTraining.Workouts.Commands.UpdateDraftWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id, params), do: WorkoutStore.update_draft(id, params)
end
