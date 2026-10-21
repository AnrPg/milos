defmodule Palee.Application.MarkMessagingThreadRead do
  alias Palee.Messaging

  def call(thread_id, user_id, message_id),
    do: Messaging.mark_read(thread_id, user_id, message_id)
end
