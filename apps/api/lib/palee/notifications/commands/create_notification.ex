defmodule Palee.Notifications.Commands.CreateNotification do
  alias Palee.Notifications.NotificationStore

  def call(params), do: NotificationStore.create_notification(params)
end
