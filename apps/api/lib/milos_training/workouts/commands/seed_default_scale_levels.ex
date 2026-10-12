defmodule MilosTraining.Workouts.Commands.SeedDefaultScaleLevels do
  @moduledoc """
  Gives an organization the default scale levels (ADR-110). Idempotent: an
  organization that already has any scale level is left untouched.
  """

  alias MilosTraining.Workouts.Domain.DefaultScaleLevels
  alias MilosTraining.Workouts.WorkoutStore

  def call(context),
    do: WorkoutStore.ensure_default_scale_levels(context, DefaultScaleLevels.levels())
end
