defmodule Palee.Notifications.Commands.MarkAllRead do
  alias Palee.Notifications.NotificationStore

  def call(user_id), do: NotificationStore.mark_all_read(user_id)
end
