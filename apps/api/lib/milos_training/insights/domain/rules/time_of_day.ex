defmodule MilosTraining.Insights.Domain.Rules.TimeOfDay do
  @moduledoc """
  Ώρα της μέρας (vision §7.7: when you perform best). Training days with
  sessions in one part of the day only (morning, afternoon, evening,
  night) count for that part; a PR day counts for its part. A finding when
  one part brings PRs at least 1.5× as often as the other parts together
  (`best_part`), or is the only part with PRs (`only_part`).

  Minimum: four weeks, two parts with six training days each, four PR
  days among them.
  """

  @behaviour MilosTraining.Insights.Domain.InsightRule

  alias MilosTraining.Insights.Domain.{InsightRule, Sufficiency}

  @min_days_per_part 6
  @min_pr_days 4
  @min_ratio 1.5

  @impl true
  def id, do: "time_of_day"
  @impl true
  def section, do: nil
  @impl true
  def item, do: nil

  @impl true
  def minimum,
    do: %{
      weeks: Sufficiency.min_weeks(),
      parts: 2,
      days_per_part: @min_days_per_part,
      pr_days: @min_pr_days
    }

  @impl true
  def compute(inputs) do
    prs = MapSet.new(inputs.pr_days)

    by_day =
      inputs.sessions
      |> Enum.map(&Sufficiency.local_of/1)
      |> Enum.group_by(&elem(&1, 0), fn {_day, hour} -> Sufficiency.part(hour) end)

    single =
      for {day, parts} <- by_day, [part] <- [Enum.uniq(parts)], do: {day, part}

    stats =
      single
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      |> Enum.map(fn {part, days} ->
        {part, length(days), Enum.count(days, &MapSet.member?(prs, &1))}
      end)
      |> Enum.filter(fn {_part, days, _prs} -> days >= @min_days_per_part end)

    pr_total = stats |> Enum.map(&elem(&1, 2)) |> Enum.sum()
    sample = %{"parts" => length(stats), "pr_days" => pr_total}

    InsightRule.gated(
      Map.keys(by_day),
      inputs.today,
      [length(stats) >= 2, pr_total >= @min_pr_days],
      sample,
      fn weeks -> best(stats, weeks, sample) end
    )
  end

  defp best(stats, weeks, sample) do
    rated = Enum.map(stats, fn {part, days, prs} -> {part, days, prs, prs / days} end)
    top_rate = rated |> Enum.map(&elem(&1, 3)) |> Enum.max()

    case Enum.filter(rated, &(elem(&1, 3) == top_rate)) do
      [{part, _days, prs, rate}] ->
        rest = Enum.reject(rated, &(elem(&1, 0) == part))
        rest_days = rest |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        rest_prs = rest |> Enum.map(&elem(&1, 2)) |> Enum.sum()

        cond do
          rest_prs == 0 and prs >= @min_pr_days ->
            InsightRule.finding(weeks, "only_part", %{"part" => part, "pr_days" => prs}, part)

          rest_prs > 0 and rate >= @min_ratio * (rest_prs / rest_days) ->
            ratio = InsightRule.ratio(rate, rest_prs / rest_days)
            InsightRule.finding(weeks, "best_part", %{"part" => part, "ratio" => ratio}, part)

          true ->
            InsightRule.no_finding(weeks, sample)
        end

      _tie ->
        InsightRule.no_finding(weeks, sample)
    end
  end
end
