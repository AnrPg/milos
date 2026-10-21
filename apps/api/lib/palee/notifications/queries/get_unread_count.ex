defmodule Palee.Notifications.Queries.GetUnreadCount do
  alias Palee.Notifications.NotificationStore

  def call(user_id), do: NotificationStore.count_unread_inbox(user_id)
end
