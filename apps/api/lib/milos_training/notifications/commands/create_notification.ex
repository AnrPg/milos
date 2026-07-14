defmodule MilosTraining.Notifications.Commands.CreateNotification do
  alias MilosTraining.Notifications.NotificationStore

  def call(params), do: NotificationStore.create_notification(params)
end
