defmodule MilosTraining.Application.MarkMessagingThreadRead do
  alias MilosTraining.Messaging

  def call(thread_id, user_id, message_id),
    do: Messaging.mark_read(thread_id, user_id, message_id)
end
