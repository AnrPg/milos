defmodule MilosTraining.Workouts.Queries.ListScaleLevels do
  alias MilosTraining.Workouts.WorkoutStore

  # ADR-110: the acting organization's active scale levels, in sort order.
  def all(context), do: WorkoutStore.list_scale_levels(context)
end
