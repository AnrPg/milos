defmodule MilosTraining.Application.ListMessagingMessages do
  alias MilosTraining.Messaging

  def call(thread_id, params), do: Messaging.list_messages(thread_id, params)
end
