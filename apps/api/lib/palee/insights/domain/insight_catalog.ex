defmodule Palee.Insights.Domain.InsightCatalog do
  @moduledoc """
  The insight rules in their fixed order, which of them apply to a member,
  and what the single Πρόοδος insights slot shows (ADR-166). Pure.

  - Rules run over the last `window_days/0` days; each has its own minimum
    sample on top of the four-week gate (`Sufficiency`).
  - A rule whose journal section is switched off (Ρυθμίσεις, vision §8.6)
    or whose wellness item is hidden produces nothing: it is stored as
    `off` with no value, and hidden on read even before the next run.
  - The slot shows at most `max_shown/0` findings, in the rules' fixed
    order (never ranked by strength, §8.5). A dismissed finding stays
    hidden until the finding itself changes (its fingerprint); the next one
    in order takes its place.
  """

  alias Palee.Insights.Domain.Rules.{
    CravingsPattern,
    Hydration,
    SleepEffort,
    SleepPRs,
    TimeOfDay
  }

  alias Palee.Insights.Domain.Sufficiency

  @rules [SleepPRs, SleepEffort, TimeOfDay, CravingsPattern, Hydration]
  @window_days 84
  @max_shown 3
  @fresh_hours 24

  def rules, do: @rules
  def rule_ids, do: Enum.map(@rules, & &1.id())
  def window_days, do: @window_days
  def window_weeks, do: div(@window_days, 7)
  def max_shown, do: @max_shown
  def min_weeks, do: Sufficiency.min_weeks()
  def statuses, do: ~w(finding no_finding insufficient off)

  @doc "The first day of the window ending `today`."
  def window_start(%Date{} = today), do: Date.add(today, -(@window_days - 1))

  @doc "Whether stored results computed at `computed_at` are still fresh at `now`."
  def fresh?(nil, _now), do: false

  def fresh?(%DateTime{} = computed_at, %DateTime{} = now),
    do: DateTime.diff(now, computed_at, :second) < @fresh_hours * 3_600

  @doc """
  Whether stored `rows` can be shown as they are at `now`: every rule has a
  row computed within the last day, and each rule is `off` exactly when it
  does not apply under the current `settings` (a section switched off or
  on since the last run means a recompute, which also clears the values of
  a section that is now off).
  """
  def current?(rows, settings, %DateTime{} = now) do
    by_rule = Map.new(rows, &{&1.rule, &1})

    Enum.all?(@rules, fn rule ->
      case Map.get(by_rule, rule.id()) do
        nil -> false
        row -> fresh?(row.computed_at, now) and applies?(rule, settings) == (row.status != "off")
      end
    end)
  end

  @doc """
  Whether `rule` applies under `settings`
  (`%{sections: %{"wellness" => bool, ...}, hidden_items: [String.t()]}`).
  """
  def applies?(rule, settings) do
    section_on?(rule.section(), settings) and item_shown?(rule.item(), settings)
  end

  defp section_on?(nil, _settings), do: true

  defp section_on?(section, settings),
    do: Map.get(Map.get(settings, :sections, %{}), section, true) != false

  defp item_shown?(nil, _settings), do: true
  defp item_shown?(item, settings), do: item not in Map.get(settings, :hidden_items, [])

  @doc """
  Every rule's result for the store: `%{rule, status, value, fingerprint}`.
  Rules that do not apply are `off` and are not computed at all.
  """
  def evaluate(inputs, settings) do
    Enum.map(@rules, fn rule ->
      if applies?(rule, settings),
        do: stored(rule.id(), rule.compute(inputs)),
        else: %{rule: rule.id(), status: "off", value: %{}, fingerprint: nil}
    end)
  end

  defp stored(id, %{status: :finding} = result) do
    %{
      rule: id,
      status: "finding",
      value: %{
        "variant" => result.variant,
        "params" => result.params,
        "weeks" => result.weeks
      },
      fingerprint: "#{id}:#{result.key}"
    }
  end

  defp stored(id, result) do
    %{
      rule: id,
      status: Atom.to_string(result.status),
      value: %{"weeks" => result.weeks, "sample" => result.sample},
      fingerprint: nil
    }
  end

  @doc """
  What the slot shows from the stored `rows` under the current `settings`:
  up to three visible findings in rule order, how many findings are
  dismissed, the weeks of data so far and the slot's state:
  `insights`, `all_hidden`, `no_pattern` (enough data, nothing clear) or
  `collecting` (not enough data yet).
  """
  def view(rows, settings) do
    by_rule = Map.new(rows, &{&1.rule, &1})

    applicable =
      for rule <- @rules,
          applies?(rule, settings),
          row = Map.get(by_rule, rule.id()),
          row,
          do: row

    findings = Enum.filter(applicable, &(&1.status == "finding"))
    {hidden, visible} = Enum.split_with(findings, &dismissed?/1)

    state =
      cond do
        visible != [] -> "insights"
        hidden != [] -> "all_hidden"
        Enum.any?(applicable, &(&1.status == "no_finding")) -> "no_pattern"
        true -> "collecting"
      end

    %{
      state: state,
      insights: Enum.take(visible, @max_shown),
      hidden_count: length(hidden),
      data_weeks: applicable |> Enum.map(&weeks/1) |> Enum.max(fn -> 0 end),
      computed_at: applicable |> Enum.map(& &1.computed_at) |> Enum.max(DateTime, fn -> nil end)
    }
  end

  def dismissed?(row),
    do: is_binary(row.fingerprint) and row.fingerprint == Map.get(row, :dismissed_fingerprint)

  defp weeks(row) do
    case Map.get(row.value || %{}, "weeks") do
      weeks when is_integer(weeks) -> weeks
      _other -> 0
    end
  end
end
