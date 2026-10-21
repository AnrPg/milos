defmodule Palee.Notifications.Commands.MarkNotificationRead do
  alias Palee.Notifications.NotificationStore

  def call(user_id, notification_id), do: NotificationStore.mark_read(user_id, notification_id)
end
