defmodule MilosTraining.Application.GetNotifications do
  alias MilosTraining.Notifications

  def call(user_id, params \\ %{}), do: Notifications.list_inbox(user_id, params)
end
