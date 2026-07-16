defmodule MilosTraining.Application.DispatchMessageDelivery do
  alias MilosTraining.Application.{
    InvalidateLandingPages,
    RealtimePublisher,
    RecordCommunicationMessage
  }

  alias MilosTraining.{Finance, Identity, Messaging, Notifications}

  def call(%{"message_id" => message_id} = delivery) do
    with %{} = message <- Messaging.get_message(message_id) || {:error, :not_found},
         {:ok, thread} <- Messaging.get_thread(message.thread_id, message.sender_id),
         :ok <- finalize_reservations(Map.get(delivery, "reservations", []), message),
         :ok <- notify_participants(thread, message),
         :ok <- invalidate_landing(thread, message),
         :ok <- record_analytics(message, thread),
         :ok <- publish(message) do
      :ok
    end
  end

  defp finalize_reservations(reservations, message) do
    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      case Finance.finalize_entitlement(reservation["reservation_id"], %{
             source_id: message.id,
             reason: "Coach check-in delivered",
             idempotency_key:
               "coach-check-in-finalized:#{reservation["delivery_id"]}:#{reservation["recipient_id"]}",
             metadata: %{"message_id" => message.id}
           }) do
        {:ok, _entry} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp publish(message) do
    RealtimePublisher.broadcast("chat:thread:#{message.thread_id}", "new_message", %{
      id: message.id,
      thread_id: message.thread_id,
      sender_id: message.sender_id,
      body: message.body,
      message_type: message.message_type,
      inserted_at: message.inserted_at
    })
  end

  defp notify_participants(thread, message) do
    thread.participants
    |> Enum.reject(&(&1.user_id == message.sender_id))
    |> Enum.reduce_while(:ok, fn participant, :ok ->
      case Notifications.create_notification(%{
             user_id: participant.user_id,
             type: :chat_message,
             dedupe_key: "chat-message:#{message.id}",
             payload: %{
               thread_id: thread.id,
               context_type: thread.context_type,
               context_id: thread.context_id,
               message_id: message.id,
               sender_id: message.sender_id,
               body: String.slice(message.body, 0, 100),
               url: "/account/activity/chats?thread=#{thread.id}"
             }
           }) do
        {:ok, _notification} -> {:cont, :ok}
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp invalidate_landing(thread, %{message_type: :coaching_note, sender_id: sender_id}) do
    thread.participants
    |> Enum.reject(&(&1.user_id == sender_id))
    |> Enum.map(& &1.user_id)
    |> InvalidateLandingPages.for_users()
  end

  defp invalidate_landing(_thread, _message), do: :ok

  defp record_analytics(message, thread) do
    users =
      thread.participants
      |> Enum.map(& &1.user_id)
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1})

    sender = Map.get(users, message.sender_id)

    thread.participants
    |> Enum.reject(&(&1.user_id == message.sender_id))
    |> Enum.reduce_while(:ok, fn participant, :ok ->
      recipient = Map.get(users, participant.user_id)

      attrs = %{
        "sender_id" => message.sender_id,
        "recipient_id" => participant.user_id,
        "thread_id" => thread.id,
        "sender_role_snapshot" => role_name(sender),
        "recipient_role_snapshot" => role_name(recipient),
        "direction" => direction(sender, recipient),
        "channel" => "in_app",
        "body" => message.body,
        "sent_at" => message.inserted_at,
        "context_type" => "messaging_#{thread.context_type}",
        "context_id" => thread.context_id || thread.id,
        "assigned_admin_id" => admin_id(sender, recipient),
        "message_params" => %{
          "context_type" => to_string(thread.context_type),
          "context_id" => thread.context_id,
          "message_type" => to_string(message.message_type),
          "message_id" => message.id
        }
      }

      case RecordCommunicationMessage.call(attrs) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp role_name(%{role: role}), do: to_string(role)
  defp role_name(_user), do: "unknown"

  defp direction(%{role: :admin}, %{role: :admin}), do: "admin_to_admin"
  defp direction(%{role: :admin}, _recipient), do: "admin_to_user"
  defp direction(_sender, %{role: :admin}), do: "user_to_admin"
  defp direction(_sender, _recipient), do: "user_to_user"

  defp admin_id(%{id: id, role: :admin}, _recipient), do: id
  defp admin_id(_sender, %{id: id, role: :admin}), do: id
  defp admin_id(_sender, _recipient), do: nil
end
