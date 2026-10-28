defmodule Palee.Gamification.Domain.WeeklyGoal do
  @moduledoc """
  A person's weekly workout goal (ADR-226): how many completed workouts make
  a week count for their streak shields, consistency and motivation scores.

  The goal is the person's own. They set it; so may the coach who coaches
  them, or the owner/admin of a box they belong to when that staff member
  may coach every client (ADR-099/100 `:manage_coaching` scope `:all`).
  Front desk and other roles never. Without a goal the platform default
  applies, so nobody is held to a number nobody chose for them.
  """

  @kind "weekly_workouts"
  @default_target 2
  @min_target 1
  @max_target 14
  @set_by_roles ~w(self coach staff)

  def kind, do: @kind
  def default_target, do: @default_target
  def min_target, do: @min_target
  def max_target, do: @max_target
  def set_by_roles, do: @set_by_roles

  @doc "The target that applies: the person's goal, else the default."
  def effective_target(%{target: target}) when is_integer(target), do: target
  def effective_target(_no_goal), do: @default_target

  @doc """
  Who is setting the goal, as stored on it: the person themselves, a coach
  with an active coaching relationship, or other staff with full coaching
  scope.
  """
  def setter_role(actor_id, member_id, _coaches?) when actor_id == member_id, do: "self"
  def setter_role(_actor_id, _member_id, true), do: "coach"
  def setter_role(_actor_id, _member_id, false), do: "staff"

  @doc "What the API returns; no goal yet means the default, set by nobody."
  def present(nil) do
    %{
      weekly_workout_target: @default_target,
      is_default: true,
      set_by_role: nil,
      set_by_id: nil,
      set_by_nickname: nil,
      updated_at: nil,
      min: @min_target,
      max: @max_target
    }
  end

  def present(goal) do
    %{
      weekly_workout_target: goal.target,
      is_default: false,
      set_by_role: goal.set_by_role,
      set_by_id: goal.set_by_id,
      set_by_nickname: Map.get(goal, :set_by_nickname),
      updated_at: goal.updated_at,
      min: @min_target,
      max: @max_target
    }
  end
end
