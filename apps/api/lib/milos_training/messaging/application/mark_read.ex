defmodule MilosTraining.Messaging.Application.MarkRead do
  alias MilosTraining.Messaging.Domain.ThreadPolicy
  alias MilosTraining.Messaging.ThreadStore

  def call(_thread_id, _user_id, nil), do: :ok

  def call(thread_id, user_id, message_id) do
    case ThreadStore.get_thread_with_participants(thread_id) do
      nil ->
        {:error, :not_found}

      thread ->
        with :ok <- ThreadPolicy.can_read?(user_id, thread) do
          with {:ok, effective_message_id} <-
                 ThreadStore.mark_read(thread_id, user_id, message_id) do
            {:ok, %{read: true, message_id: effective_message_id}}
          end
        end
    end
  end
end
