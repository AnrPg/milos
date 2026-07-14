defmodule MilosTraining.Analytics.Commands.RecordCommunicationMessage do
  alias MilosTraining.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.record_communication_message(params)
end
