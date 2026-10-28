defmodule Palee.Application.GetUnreadNotificationCount do
  alias Palee.Notifications

  def call(user_id), do: Notifications.unread_count(user_id)
end
