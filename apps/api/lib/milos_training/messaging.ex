defmodule MilosTraining.Messaging do
  alias MilosTraining.Messaging.Application.{
    GetOrCreateThread,
    SendMessage,
    ListMessages,
    ListThreads,
    MarkRead,
    GetThread
  }

  defdelegate get_or_create_thread(params), to: GetOrCreateThread, as: :call
  defdelegate send_message(params), to: SendMessage, as: :call
  defdelegate send_message(params, delivery), to: SendMessage, as: :call
  defdelegate list_messages(thread_id, params), to: ListMessages, as: :call
  defdelegate list_threads_for_user(user_id, context_type \\ nil), to: ListThreads, as: :call
  defdelegate mark_read(thread_id, user_id, message_id), to: MarkRead, as: :call
  defdelegate get_thread(thread_id, user_id), to: GetThread, as: :call
  def get_message(message_id), do: MilosTraining.Messaging.MessageStore.get_message(message_id)

  def list_recent_coaching_notes(user_id, limit \\ 5)
      when is_integer(limit) and limit in 1..50,
      do: MilosTraining.Messaging.MessageStore.list_recent_coaching_notes(user_id, limit)

  def count_unread_threads(user_id),
    do: MilosTraining.Messaging.ThreadStore.count_unread_threads(user_id)
end
