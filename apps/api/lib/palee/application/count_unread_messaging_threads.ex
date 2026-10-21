defmodule Palee.Application.CountUnreadMessagingThreads do
  alias Palee.Messaging

  def call(user_id), do: Messaging.count_unread_threads(user_id)
end
