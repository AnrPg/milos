defmodule MilosTraining.Application.ListScaleLevels do
  alias MilosTraining.Workouts

  # ADR-110: the acting tenant's scale levels only.
  def call(context), do: Workouts.list_scale_levels(context)
end
