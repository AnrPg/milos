defmodule MilosTraining.Workouts.Queries.ListScaleLevels do
  alias MilosTraining.Workouts.WorkoutStore

  def all, do: WorkoutStore.list_scale_levels()
end
