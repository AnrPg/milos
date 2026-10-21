defmodule Palee.Workouts.Queries.ListScaleLevels do
  alias Palee.Workouts.WorkoutStore

  # ADR-128: the acting organization's active scale levels, in sort order.
  def all(context), do: WorkoutStore.list_scale_levels(context)
end
