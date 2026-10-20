defmodule MilosTraining.Wellness.Domain.PreferencesPolicy do
  @moduledoc """
  The member's own wellness targets (ADR-159 §4, vision §8.6): the water goal
  and glass size, the sleep goal, and the items they turned off. Targets are
  the member's; a coach may suggest but never sets them.
  """

  @items ~w(water sleep meals plan mood)

  @defaults %{water_goal_ml: 2_000, glass_ml: 250, sleep_goal_minutes: 420, hidden_items: []}

  def items, do: @items
  def defaults, do: @defaults
end
