defmodule MilosTraining.Application.GetPushNotificationConfig do
  alias MilosTraining.Notifications

  def call, do: Notifications.push_config()
end
