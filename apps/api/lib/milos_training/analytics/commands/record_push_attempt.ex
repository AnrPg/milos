defmodule MilosTraining.Analytics.Commands.RecordPushAttempt do
  alias MilosTraining.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.record_push_attempt(params)
end
