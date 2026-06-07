defmodule MilosTraining.Workouts.Commands.ReplaceScaleLevels do
  alias MilosTraining.Workouts.WorkoutStore

  def call(levels), do: WorkoutStore.replace_scale_levels(levels)
end
