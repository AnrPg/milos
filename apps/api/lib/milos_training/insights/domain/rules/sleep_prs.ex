defmodule MilosTraining.Insights.Domain.Rules.SleepPRs do
  @moduledoc """
  Ύπνος ↔ PR (vision §7.7: «PR 2,4× more often after 7h+ sleep»). Training
  days with the night before logged are split by the member's own sleep
  goal; a finding when PRs come at least 1.5× as often after reaching it
  (`more_after_goal`), or only after reaching it (`all_after_goal`).

  Minimum: four weeks, five training days on each side, three PR days.
  """

  @behaviour MilosTraining.Insights.Domain.InsightRule

  alias MilosTraining.Insights.Domain.{InsightRule, Sufficiency}

  @min_days_per_side 5
  @min_pr_days 3
  @min_ratio 1.5

  @impl true
  def id, do: "sleep_prs"
  @impl true
  def section, do: "wellness"
  @impl true
  def item, do: "sleep"

  @impl true
  def minimum,
    do: %{
      weeks: Sufficiency.min_weeks(),
      days_per_side: @min_days_per_side,
      pr_days: @min_pr_days
    }

  @impl true
  def compute(inputs) do
    goal = inputs.sleep_goal_minutes
    nights = Sufficiency.nights(inputs.days)
    prs = MapSet.new(inputs.pr_days)

    pairs =
      for day <- Sufficiency.training_days(inputs.sessions),
          minutes = Map.get(nights, day),
          is_integer(minutes),
          do: {day, minutes >= goal}

    {rested, short} = Enum.split_with(pairs, fn {_day, rested?} -> rested? end)
    pr_rested = Enum.count(rested, fn {day, _} -> MapSet.member?(prs, day) end)
    pr_short = Enum.count(short, fn {day, _} -> MapSet.member?(prs, day) end)

    sample = %{"rested_days" => length(rested), "short_days" => length(short)}

    InsightRule.gated(
      Enum.map(pairs, &elem(&1, 0)),
      inputs.today,
      [
        length(rested) >= @min_days_per_side,
        length(short) >= @min_days_per_side,
        pr_rested + pr_short >= @min_pr_days
      ],
      sample,
      fn weeks ->
        hours = InsightRule.hours(goal)

        cond do
          pr_short == 0 and pr_rested >= @min_pr_days ->
            InsightRule.finding(
              weeks,
              "all_after_goal",
              %{"hours" => hours, "pr_days" => pr_rested},
              nil
            )

          pr_short > 0 and
              pr_rested / length(rested) >= @min_ratio * (pr_short / length(short)) ->
            ratio = InsightRule.ratio(pr_rested / length(rested), pr_short / length(short))

            InsightRule.finding(
              weeks,
              "more_after_goal",
              %{"hours" => hours, "ratio" => ratio},
              nil
            )

          true ->
            InsightRule.no_finding(weeks, sample)
        end
      end
    )
  end
end
