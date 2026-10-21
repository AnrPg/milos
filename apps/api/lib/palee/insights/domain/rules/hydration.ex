defmodule Palee.Insights.Domain.Rules.Hydration do
  @moduledoc """
  Νερό (vision §7.7: % days on target). Of the days with water logged, how
  many reached the member's own goal; when training days and rest days
  differ by 20 points or more (five logged days each), which way
  (`training_more`, `training_less`), else `on_goal`. Only against the
  member's own goal, never a norm.

  Minimum: four weeks, fourteen days with water logged.
  """

  @behaviour Palee.Insights.Domain.InsightRule

  alias Palee.Insights.Domain.{InsightRule, Sufficiency}

  @min_logged_days 14
  @min_days_per_side 5
  @min_gap 20

  @impl true
  def id, do: "hydration"
  @impl true
  def section, do: "wellness"
  @impl true
  def item, do: "water"

  @impl true
  def minimum,
    do: %{
      weeks: Sufficiency.min_weeks(),
      logged_days: @min_logged_days,
      days_per_side: @min_days_per_side
    }

  @impl true
  def compute(inputs) do
    logged = Enum.filter(inputs.days, &(&1.water.ml > 0))
    sample = %{"logged_days" => length(logged)}

    InsightRule.gated(
      Enum.map(logged, & &1.date),
      inputs.today,
      [length(logged) >= @min_logged_days],
      sample,
      fn weeks ->
        training = Sufficiency.training_days(inputs.sessions)
        {on_training, on_rest} = Enum.split_with(logged, &MapSet.member?(training, &1.date))
        training_percent = percent(on_training, @min_days_per_side)
        rest_percent = percent(on_rest, @min_days_per_side)

        variant =
          cond do
            is_nil(training_percent) or is_nil(rest_percent) -> "on_goal"
            training_percent - rest_percent >= @min_gap -> "training_more"
            rest_percent - training_percent >= @min_gap -> "training_less"
            true -> "on_goal"
          end

        params = %{
          "logged_days" => length(logged),
          "on_goal_days" => Enum.count(logged, &on_goal?/1),
          "percent" => percent(logged, 1),
          "training_percent" => training_percent,
          "rest_percent" => rest_percent
        }

        InsightRule.finding(weeks, variant, params, nil)
      end
    )
  end

  defp on_goal?(day), do: day.water.status == "full"

  defp percent(days, minimum) when length(days) < minimum, do: nil
  defp percent(days, _minimum), do: round(Enum.count(days, &on_goal?/1) * 100 / length(days))
end
