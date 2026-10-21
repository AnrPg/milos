defmodule Palee.Workouts.Commands.SeedDefaultScaleLevels do
  @moduledoc """
  Gives an organization the default scale levels (ADR-128). Idempotent: an
  organization that already has any scale level is left untouched.
  """

  alias Palee.Workouts.Domain.DefaultScaleLevels
  alias Palee.Workouts.WorkoutStore

  def call(context),
    do: WorkoutStore.ensure_default_scale_levels(context, DefaultScaleLevels.levels())
end
