defmodule MilosTraining.Notifications.Commands.MarkAllRead do
  alias MilosTraining.Notifications.NotificationStore

  def call(user_id), do: NotificationStore.mark_all_read(user_id)
end
