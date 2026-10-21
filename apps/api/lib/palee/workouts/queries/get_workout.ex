defmodule Palee.Workouts.Queries.GetWorkout do
  alias Palee.Workouts.WorkoutStore

  def by_id(context, id), do: WorkoutStore.get_workout(context, id)
end
