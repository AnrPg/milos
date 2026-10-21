defmodule Palee.Application.GetNotifications do
  alias Palee.Notifications

  def call(user_id, params \\ %{}), do: Notifications.list_inbox(user_id, params)
end
