defmodule Palee.Analytics.Commands.RecordCommunicationMessage do
  alias Palee.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.record_communication_message(params)
end
