defmodule MilosTraining.Insights do
  @moduledoc """
  Insights bounded context (ADR-166; vision §7.7, §8.6): correlations and
  patterns from the member's own sleep, water, cravings, sessions and PRs,
  computed nightly by fixed rules, shown in one Πρόοδος slot only once
  there is enough data, always as an indicator and never medical advice.
  Account data, the owner's alone.
  """

  alias MilosTraining.Insights.Domain.{InsightCatalog, Sufficiency}
  alias MilosTraining.Insights.InsightStore

  defdelegate with_context(context, fun), to: InsightStore

  # Domain.
  defdelegate rules(), to: InsightCatalog
  defdelegate rule_ids(), to: InsightCatalog
  defdelegate window_days(), to: InsightCatalog
  defdelegate window_weeks(), to: InsightCatalog
  defdelegate window_start(today), to: InsightCatalog
  defdelegate max_shown(), to: InsightCatalog
  defdelegate min_weeks(), to: InsightCatalog
  defdelegate parts(), to: Sufficiency
  defdelegate current?(rows, settings, now), to: InsightCatalog
  defdelegate evaluate(inputs, settings), to: InsightCatalog
  defdelegate view(rows, settings), to: InsightCatalog

  # Store.
  defdelegate list(user_id), to: InsightStore
  defdelegate put_results(user_id, results, from, to, now), to: InsightStore
  defdelegate dismiss(user_id, rule, now), to: InsightStore
  defdelegate restore(user_id), to: InsightStore
  defdelegate delete_all(user_id), to: InsightStore
  defdelegate candidates(since, after_id, limit), to: InsightStore
end
