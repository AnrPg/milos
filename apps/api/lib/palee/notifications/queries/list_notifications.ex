defmodule Palee.Notifications.Queries.ListNotifications do
  alias Palee.Notifications.Domain.VisibleTypes
  alias Palee.Notifications.NotificationStore

  def for_user(user_id) do
    user_id
    |> NotificationStore.list_for_user()
    |> Enum.filter(&VisibleTypes.visible_inbox_type?(&1.type))
  end
end
