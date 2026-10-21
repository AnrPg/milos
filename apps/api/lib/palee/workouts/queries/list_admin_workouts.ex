defmodule Palee.Workouts.Queries.ListAdminWorkouts do
  alias Palee.Workouts.WorkoutStore

  def all(context), do: WorkoutStore.list_workouts(context)
end
