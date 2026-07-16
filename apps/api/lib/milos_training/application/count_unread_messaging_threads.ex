defmodule MilosTraining.Application.CountUnreadMessagingThreads do
  alias MilosTraining.Messaging

  def call(user_id), do: Messaging.count_unread_threads(user_id)
end
