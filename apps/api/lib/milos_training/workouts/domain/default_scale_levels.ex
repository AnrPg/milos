defmodule MilosTraining.Workouts.Domain.DefaultScaleLevels do
  @moduledoc """
  The scale levels every new organization starts with (ADR-118).

  Scale levels are tenant-owned; a gym can rename, reorder or replace them
  through `PUT /api/org/:slug/admin/scale-levels`. This is only the starting
  set seeded at provisioning, matching the set the platform has always shipped
  (`Scaled / Rx / Rx+`).
  """

  @levels [
    %{slug: "scaled", label: "Scaled", sort_order: 1},
    %{slug: "rx", label: "Rx", sort_order: 2},
    %{slug: "rx-plus", label: "Rx+", sort_order: 3}
  ]

  @spec levels() :: [%{slug: String.t(), label: String.t(), sort_order: pos_integer()}]
  def levels, do: @levels
end
