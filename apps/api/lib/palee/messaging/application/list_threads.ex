defmodule Palee.Messaging.Application.ListThreads do
  alias Palee.Messaging.ThreadStore

  def call(user_id, context_type \\ nil) do
    ThreadStore.list_threads_for_user(user_id, context_type)
  end
end
