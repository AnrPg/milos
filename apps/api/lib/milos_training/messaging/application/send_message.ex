defmodule MilosTraining.Messaging.Application.SendMessage do
  alias MilosTraining.Messaging.Domain.ThreadPolicy
  alias MilosTraining.Messaging.{MessageStore, ThreadStore}

  def call(params, delivery \\ %{})

  def call(%{thread_id: thread_id, sender_id: sender_id, body: body} = params, delivery) do
    message_type = Map.get(params, :message_type, :chat)
    client_operation_id = Map.get(params, :client_operation_id)

    with %{} = thread <-
           ThreadStore.get_thread_with_participants(thread_id) || {:error, :not_found},
         :ok <- ThreadPolicy.can_send?(sender_id, thread),
         {:ok, message} <-
           MessageStore.create_message_with_delivery(
             %{
               thread_id: thread_id,
               sender_id: sender_id,
               body: body,
               message_type: message_type,
               client_operation_id: client_operation_id
             },
             delivery
           ) do
      {:ok, message}
    end
  end
end
