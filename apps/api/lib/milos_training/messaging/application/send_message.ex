defmodule MilosTraining.Messaging.Application.SendMessage do
  require Logger

  alias MilosTraining.Application.{InvalidateLandingPages, RecordCommunicationMessage}
  alias MilosTraining.Messaging.Domain.ThreadPolicy
  alias MilosTraining.Messaging.{MessageStore, ThreadStore}
  alias MilosTraining.Notifications

  def call(%{thread_id: thread_id, sender_id: sender_id, body: body} = params) do
    message_type = Map.get(params, :message_type, :chat)

    with %{} = thread <-
           ThreadStore.get_thread_with_participants(thread_id) || {:error, :not_found},
         :ok <- ThreadPolicy.can_send?(sender_id, thread),
         {:ok, message} <-
           MessageStore.create_message(%{
             thread_id: thread_id,
             sender_id: sender_id,
             body: body,
             message_type: message_type
           }) do
      broadcast_to_thread(thread_id, message)
      notify_other_participants(thread, sender_id, message)
      maybe_invalidate_landing(thread, sender_id, message)
      record_analytics(message, thread)
      {:ok, message}
    end
  end

  defp broadcast_to_thread(thread_id, message) do
    MilosTrainingWeb.Endpoint.broadcast(
      "chat:thread:#{thread_id}",
      "new_message",
      serialize_message(message)
    )
  end

  defp notify_other_participants(thread, sender_id, message) do
    thread.participants
    |> Enum.reject(&(&1.user_id == sender_id))
    |> Enum.each(fn participant ->
      Notifications.create_notification(%{
        user_id: participant.user_id,
        type: :chat_message,
        payload: %{
          thread_id: thread.id,
          context_type: thread.context_type,
          context_id: thread.context_id,
          message_id: message.id,
          sender_id: sender_id,
          body: String.slice(message.body, 0, 100),
          url: "/account/activity/chats?thread=#{thread.id}"
        }
      })
    end)
  end

  defp maybe_invalidate_landing(thread, sender_id, %{message_type: :coaching_note}) do
    thread.participants
    |> Enum.reject(&(&1.user_id == sender_id))
    |> Enum.each(fn participant ->
      InvalidateLandingPages.for_user(participant.user_id)
    end)
  end

  defp maybe_invalidate_landing(_thread, _sender_id, _message), do: :ok

  defp record_analytics(message, thread) do
    RecordCommunicationMessage.call_unsafe(%{
      "sender_id" => message.sender_id,
      "thread_id" => thread.id,
      "context_type" => to_string(thread.context_type),
      "message_type" => to_string(message.message_type),
      "sent_at" => message.inserted_at
    })
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      thread_id: message.thread_id,
      sender_id: message.sender_id,
      body: message.body,
      message_type: message.message_type,
      inserted_at: message.inserted_at
    }
  end
end
