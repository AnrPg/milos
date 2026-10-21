defmodule Palee.Application.ListScaleLevels do
  alias Palee.Workouts

  # ADR-128: the acting tenant's scale levels only.
  def call(context), do: Workouts.list_scale_levels(context)
end
