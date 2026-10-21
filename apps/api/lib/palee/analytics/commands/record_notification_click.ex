defmodule Palee.Analytics.Commands.RecordNotificationClick do
  alias Palee.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.record_notification_click(params)
end
