defmodule Palee.Insights.Domain.Rules.SleepEffort do
  @moduledoc """
  Ύπνος ↔ πώς βγαίνει η προπόνηση: sessions with a perceived effort (RPE)
  and the night before logged, split by the member's own sleep goal. A
  finding when sessions after a shorter night are rated at least one point
  harder on average (`harder_after_short`). Perceived effort only: the copy
  never says the training was worse.

  Minimum: four weeks, five rated sessions on each side.
  """

  @behaviour Palee.Insights.Domain.InsightRule

  alias Palee.Insights.Domain.{InsightRule, Sufficiency}

  @min_sessions_per_side 5
  @min_delta 1.0

  @impl true
  def id, do: "sleep_effort"
  @impl true
  def section, do: "wellness"
  @impl true
  def item, do: "sleep"

  @impl true
  def minimum, do: %{weeks: Sufficiency.min_weeks(), sessions_per_side: @min_sessions_per_side}

  @impl true
  def compute(inputs) do
    goal = inputs.sleep_goal_minutes
    nights = Sufficiency.nights(inputs.days)

    rated =
      for %{rpe: rpe} = session <- inputs.sessions,
          is_integer(rpe),
          {day, _hour} = Sufficiency.local_of(session),
          minutes = Map.get(nights, day),
          is_integer(minutes),
          do: {day, rpe, minutes >= goal}

    {rested, short} = Enum.split_with(rated, fn {_day, _rpe, rested?} -> rested? end)
    sample = %{"rested_sessions" => length(rested), "short_sessions" => length(short)}

    InsightRule.gated(
      Enum.map(rated, &elem(&1, 0)),
      inputs.today,
      [length(rested) >= @min_sessions_per_side, length(short) >= @min_sessions_per_side],
      sample,
      fn weeks ->
        delta =
          Sufficiency.mean(Enum.map(short, &elem(&1, 1))) -
            Sufficiency.mean(Enum.map(rested, &elem(&1, 1)))

        if delta >= @min_delta do
          InsightRule.finding(
            weeks,
            "harder_after_short",
            %{"hours" => InsightRule.hours(goal), "delta" => Float.round(delta, 1)},
            nil
          )
        else
          InsightRule.no_finding(weeks, sample)
        end
      end
    )
  end
end
