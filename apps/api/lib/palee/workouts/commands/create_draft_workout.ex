defmodule Palee.Workouts.Commands.CreateDraftWorkout do
  alias Palee.Workouts.WorkoutStore

  def call(admin_id), do: WorkoutStore.create_draft(admin_id)
end
