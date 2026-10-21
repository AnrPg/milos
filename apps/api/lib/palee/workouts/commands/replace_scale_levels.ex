defmodule Palee.Workouts.Commands.ReplaceScaleLevels do
  alias Palee.Workouts.WorkoutStore

  # ADR-128: replaces only the acting organization's set.
  def call(context, levels), do: WorkoutStore.replace_scale_levels(context, levels)
end
