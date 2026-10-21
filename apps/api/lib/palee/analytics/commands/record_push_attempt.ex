defmodule Palee.Analytics.Commands.RecordPushAttempt do
  alias Palee.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.record_push_attempt(params)
end
