defmodule MilosTraining.Analytics.Queries.AnalyticsSummary do
  alias MilosTraining.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.analytics_summary(params)
end
