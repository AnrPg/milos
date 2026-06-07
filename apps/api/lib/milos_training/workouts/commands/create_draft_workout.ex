defmodule MilosTraining.Workouts.Commands.CreateDraftWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(admin_id), do: WorkoutStore.create_draft(admin_id)
end
