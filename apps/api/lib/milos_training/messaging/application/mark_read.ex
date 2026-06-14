defmodule MilosTraining.Messaging.Application.MarkRead do
  alias MilosTraining.Messaging.Domain.ThreadPolicy
  alias MilosTraining.Messaging.ThreadStore

  def call(thread_id, user_id, message_id) do
    case ThreadStore.get_thread_with_participants(thread_id) do
      nil ->
        {:error, :not_found}

      thread ->
        with :ok <- ThreadPolicy.can_read?(user_id, thread) do
          ThreadStore.mark_read(thread_id, user_id, message_id)
        end
    end
  end
end
