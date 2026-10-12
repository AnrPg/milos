defmodule MilosTraining.Workouts.Commands.ReplaceScaleLevels do
  alias MilosTraining.Workouts.WorkoutStore

  # ADR-110: replaces only the acting organization's set.
  def call(context, levels), do: WorkoutStore.replace_scale_levels(context, levels)
end
