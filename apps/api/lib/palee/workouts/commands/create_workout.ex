defmodule Palee.Workouts.Commands.CreateWorkout do
  alias Palee.Workouts.WorkoutStore

  def call(admin_id, params), do: WorkoutStore.create_workout(admin_id, params)
end
