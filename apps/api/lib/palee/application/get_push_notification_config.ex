defmodule Palee.Application.GetPushNotificationConfig do
  alias Palee.Notifications

  def call, do: Notifications.push_config()
end
