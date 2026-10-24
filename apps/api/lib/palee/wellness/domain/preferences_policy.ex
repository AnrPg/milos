defmodule Palee.Wellness.Domain.PreferencesPolicy do
  @moduledoc """
  The member's own wellness targets (ADR-159 §4, vision §8.6): the water goal
  and glass size, the sleep goal, and the items they turned off. Targets are
  the member's; a coach may suggest but never sets them. The tiles come in
  the member's own order (board 14, Q1); items they never placed follow in
  the default order, so a new item never disappears. The macros of a coach's
  nutrition plan show only while there is a plan, and the member can hide
  them (`hide_macros`, ADR-194).
  """

  @items ~w(water sleep meals plan mood)

  @defaults %{
    water_goal_ml: 2_000,
    glass_ml: 250,
    sleep_goal_minutes: 420,
    hidden_items: [],
    item_order: [],
    water_reminder: true,
    hide_macros: false
  }

  def items, do: @items
  def defaults, do: @defaults

  def ordered_items(item_order) when is_list(item_order),
    do: Enum.uniq(Enum.filter(item_order, &(&1 in @items)) ++ @items)
end
