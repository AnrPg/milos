defmodule Palee.Application.ListMessagingMessages do
  alias Palee.Messaging

  def call(thread_id, params), do: Messaging.list_messages(thread_id, params)
end
