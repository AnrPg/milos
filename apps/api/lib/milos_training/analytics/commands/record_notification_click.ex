defmodule MilosTraining.Analytics.Commands.RecordNotificationClick do
  alias MilosTraining.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.record_notification_click(params)
end
