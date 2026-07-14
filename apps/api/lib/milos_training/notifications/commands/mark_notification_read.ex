defmodule MilosTraining.Notifications.Commands.MarkNotificationRead do
  alias MilosTraining.Notifications.NotificationStore

  def call(user_id, notification_id), do: NotificationStore.mark_read(user_id, notification_id)
end
