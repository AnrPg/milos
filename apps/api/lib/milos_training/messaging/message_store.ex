defmodule MilosTraining.Messaging.MessageStore do
  @behaviour MilosTraining.Messaging.Ports.MessageStore

  @impl true
  def create_message(attrs), do: impl().create_message(attrs)
  @impl true
  def create_message_with_delivery(attrs, delivery),
    do: impl().create_message_with_delivery(attrs, delivery)

  @impl true
  def list_messages(thread_id, params), do: impl().list_messages(thread_id, params)
  @impl true
  def get_message(id), do: impl().get_message(id)
  @impl true
  def list_recent_coaching_notes(user_id, limit),
    do: impl().list_recent_coaching_notes(user_id, limit)

  defp impl do
    Application.fetch_env!(:milos_training, :messaging_message_store)
  end
end
