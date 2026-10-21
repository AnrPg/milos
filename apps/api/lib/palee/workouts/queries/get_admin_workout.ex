defmodule Palee.Workouts.Queries.GetAdminWorkout do
  alias Palee.Workouts.WorkoutStore

  def by_id(context, id), do: WorkoutStore.get_workout_for_admin(context, id)
end
