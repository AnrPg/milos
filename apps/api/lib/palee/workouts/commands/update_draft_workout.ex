defmodule Palee.Workouts.Commands.UpdateDraftWorkout do
  alias Palee.Workouts.WorkoutStore

  def call(id, params), do: WorkoutStore.update_draft(id, params)
end
