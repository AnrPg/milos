defmodule MilosTraining.Analytics.Commands.RecordEvent do
  alias MilosTraining.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.record_event(params)
end
