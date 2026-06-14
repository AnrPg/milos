defmodule MilosTraining.Messaging.Application.ListMessages do
  alias MilosTraining.Messaging.Domain.ThreadPolicy
  alias MilosTraining.Messaging.{MessageStore, ThreadStore}

  def call(thread_id, params \\ %{}) do
    case ThreadStore.get_thread_with_participants(thread_id) do
      nil ->
        {:error, :not_found}

      thread ->
        actor_id = Map.get(params, :actor_id)

        if actor_id && ThreadPolicy.can_read?(actor_id, thread) != :ok do
          {:error, :forbidden}
        else
          messages = MessageStore.list_messages(thread_id, params)
          {:ok, messages}
        end
    end
  end
end
