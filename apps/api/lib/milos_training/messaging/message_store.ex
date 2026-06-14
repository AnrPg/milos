defmodule MilosTraining.Messaging.MessageStore do
  @behaviour MilosTraining.Messaging.Ports.MessageStore

  @impl true
  def create_message(attrs), do: impl().create_message(attrs)
  @impl true
  def list_messages(thread_id, params), do: impl().list_messages(thread_id, params)
  @impl true
  def get_message(id), do: impl().get_message(id)

  defp impl do
    Application.get_env(
      :milos_training,
      :messaging_message_store,
      MilosTraining.Infrastructure.Messaging.EctoMessageStore
    )
  end
end
