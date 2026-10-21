defmodule MilosTraining.Insights.Domain.Rules.CravingsPattern do
  @moduledoc """
  Λιγούρες (vision §7.7: frequency, triggers, time). A finding when at least
  half of the cravings come in one part of the day, and/or one cause
  (stress, fatigue, boredom, social, hunger; never «other») is named in at
  least 40% of the cravings that have a cause. Neutral copy only: when and
  with what, never a judgement (§8.6).

  Minimum: four weeks, eight cravings (five with a cause for the cause).
  """

  @behaviour MilosTraining.Insights.Domain.InsightRule

  alias MilosTraining.Insights.Domain.{InsightRule, Sufficiency}

  @min_cravings 8
  @min_with_trigger 5
  @part_share 0.5
  @trigger_share 0.4

  @impl true
  def id, do: "cravings"
  @impl true
  def section, do: "cravings"
  @impl true
  def item, do: nil

  @impl true
  def minimum,
    do: %{weeks: Sufficiency.min_weeks(), cravings: @min_cravings, with_cause: @min_with_trigger}

  @impl true
  def compute(inputs) do
    placed =
      Enum.map(inputs.cravings, fn craving ->
        {day, hour} = Sufficiency.local(craving.occurred_at, Map.get(craving, :occurred_tz))
        {day, Sufficiency.part(hour), List.wrap(Map.get(craving, :triggers))}
      end)

    total = length(placed)
    sample = %{"cravings" => total}

    InsightRule.gated(
      Enum.map(placed, &elem(&1, 0)),
      inputs.today,
      [total >= @min_cravings],
      sample,
      fn weeks ->
        {part, part_count} = top(Enum.map(placed, &elem(&1, 1)))
        with_trigger = Enum.filter(placed, fn {_day, _part, triggers} -> triggers != [] end)

        {trigger, trigger_count} =
          with_trigger
          |> Enum.flat_map(fn {_day, _part, triggers} -> Enum.uniq(triggers) end)
          |> Enum.reject(&(&1 == "other"))
          |> top()

        part = if part && part_count >= @part_share * total, do: part
        trigger_base = length(with_trigger)

        trigger =
          if trigger && trigger_base >= @min_with_trigger &&
               trigger_count >= @trigger_share * trigger_base,
             do: trigger

        params = %{
          "total" => total,
          "part" => part,
          "part_count" => if(part, do: part_count),
          "trigger" => trigger,
          "trigger_count" => if(trigger, do: trigger_count),
          "with_trigger" => trigger_base
        }

        case {part, trigger} do
          {nil, nil} -> InsightRule.no_finding(weeks, sample)
          {nil, _} -> InsightRule.finding(weeks, "trigger", params, trigger)
          {_, nil} -> InsightRule.finding(weeks, "part", params, part)
          {_, _} -> InsightRule.finding(weeks, "part_and_trigger", params, [part, trigger])
        end
      end
    )
  end

  # The most frequent value, nil on a tie or when there is none.
  defp top([]), do: {nil, 0}

  defp top(values) do
    counts = Enum.frequencies(values)
    max = counts |> Map.values() |> Enum.max()

    case Enum.filter(counts, fn {_value, count} -> count == max end) do
      [{value, count}] -> {value, count}
      _tie -> {nil, 0}
    end
  end
end
