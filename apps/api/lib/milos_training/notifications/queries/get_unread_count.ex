defmodule MilosTraining.Notifications.Queries.GetUnreadCount do
  alias MilosTraining.Notifications.NotificationStore

  def call(user_id), do: NotificationStore.count_unread_inbox(user_id)
end
