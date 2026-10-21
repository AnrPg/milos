defmodule Palee.Analytics.Queries.AnalyticsSummary do
  alias Palee.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.analytics_summary(params)
end
