defmodule Palee.Gamification.Domain.Level do
  @moduledoc """
  «Επίπεδο» (ADR-285): experience points (XP) earned from what the person
  did, and the level they reach. XP is never stored. It is worked out from
  the stats every time, so voiding a workout or a correction to the stats
  always shows in it and nothing can be counted twice.

  The points per fact and the level curve are the product's choice
  (ANR 2026-10-30 approved the mockup values); they live only here.

  * a completed workout: 50 XP
  * a PR, found in a workout or beaten by hand: 100 XP
  * a week on the weekly goal: 150 XP
  * a completed challenge: 300 XP

  Going from level `n` to `n + 1` takes `200 + 100 × (n - 1)` XP, so the
  first level comes after about four workouts and each next one takes a
  little longer.
  """

  @points %{workouts: 50, prs: 100, weeks_on_goal: 150, challenges: 300}
  @first_step 200
  @step_growth 100

  @type stats :: %{
          optional(:total_workouts) => non_neg_integer() | nil,
          optional(:total_prs) => non_neg_integer() | nil,
          optional(:advancement_count) => non_neg_integer() | nil,
          optional(:weeks_on_goal) => non_neg_integer() | nil,
          optional(:challenges_completed) => non_neg_integer() | nil
        }

  @type t :: %{
          level: pos_integer(),
          xp: non_neg_integer(),
          level_start_xp: non_neg_integer(),
          next_level_xp: pos_integer(),
          points: %{atom() => pos_integer()}
        }

  @doc "XP per fact, for the explainer."
  def points, do: @points

  @doc "Total XP from the stats."
  @spec xp(stats()) :: non_neg_integer()
  def xp(stats) do
    facts = %{
      workouts: count(stats, :total_workouts),
      prs: count(stats, :total_prs) + count(stats, :advancement_count),
      weeks_on_goal: count(stats, :weeks_on_goal),
      challenges: count(stats, :challenges_completed)
    }

    Enum.reduce(@points, 0, fn {fact, points}, total -> total + points * facts[fact] end)
  end

  @doc "The level for the stats, with where the current level starts and ends."
  @spec present(stats() | nil) :: t()
  def present(stats) do
    xp = xp(stats || %{})
    {level, start} = level_for(xp, 1, 0)

    %{
      level: level,
      xp: xp,
      level_start_xp: start,
      next_level_xp: start + step(level),
      points: @points
    }
  end

  @doc "XP needed to go from `level` to the next one."
  @spec step(pos_integer()) :: pos_integer()
  def step(level) when is_integer(level) and level >= 1,
    do: @first_step + @step_growth * (level - 1)

  defp level_for(xp, level, start) do
    next = start + step(level)
    if xp >= next, do: level_for(xp, level + 1, next), else: {level, start}
  end

  defp count(stats, key) do
    case Map.get(stats, key) do
      value when is_integer(value) and value > 0 -> value
      _missing -> 0
    end
  end
end
