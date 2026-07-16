defmodule MilosTraining.Application.GetMessagingThread do
  alias MilosTraining.Messaging

  def call(thread_id, user_id), do: Messaging.get_thread(thread_id, user_id)
end
