defmodule MilosTraining.Messaging.ThreadStore do
  @behaviour MilosTraining.Messaging.Ports.ThreadStore

  @impl true
  def get_thread(id), do: impl().get_thread(id)
  @impl true
  def get_thread_with_participants(id), do: impl().get_thread_with_participants(id)
  @impl true
  def find_direct_thread(a, b), do: impl().find_direct_thread(a, b)
  @impl true
  def find_context_thread(type, id), do: impl().find_context_thread(type, id)
  @impl true
  def list_threads_for_user(user_id, context_type),
    do: impl().list_threads_for_user(user_id, context_type)

  @impl true
  def create_thread(attrs), do: impl().create_thread(attrs)
  @impl true
  def add_participant(thread_id, user_id), do: impl().add_participant(thread_id, user_id)
  @impl true
  def mark_read(thread_id, user_id, message_id),
    do: impl().mark_read(thread_id, user_id, message_id)

  defp impl do
    Application.get_env(
      :milos_training,
      :messaging_thread_store,
      MilosTraining.Infrastructure.Messaging.EctoThreadStore
    )
  end
end
