defmodule Palee.Application.DispatchMessageDelivery do
  alias Palee.Application.{
    InvalidateLandingPages,
    RealtimePublisher,
    RecordCommunicationMessage
  }

  alias Palee.{Finance, Identity, Messaging, Notifications, Organizations}

  def call(tenant_context, %{"organization_id" => organization_id} = delivery) do
    with true <- tenant_organization_id(tenant_context) == organization_id do
      Messaging.with_tenant_context(tenant_context, fn -> call(delivery) end)
    else
      false -> {:error, :organization_scope_mismatch}
    end
  end

  def call(%{"message_id" => message_id, "organization_id" => organization_id} = delivery) do
    with %{} = message <- Messaging.get_message(message_id) || {:error, :not_found},
         {:ok, thread} <- Messaging.get_thread(message.thread_id, message.sender_id),
         true <- thread.organization_id == organization_id,
         :ok <- finalize_reservations(Map.get(delivery, "reservations", []), message),
         :ok <- notify_participants(thread, message),
         :ok <- invalidate_landing(thread, message),
         :ok <- record_analytics(message, thread),
         :ok <- publish(message, thread) do
      :ok
    else
      false -> {:error, :organization_scope_mismatch}
      error -> error
    end
  end

  defp tenant_organization_id(%{organization_id: organization_id}), do: organization_id
  defp tenant_organization_id(_context), do: nil

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

  defp publish(message, thread) do
    RealtimePublisher.broadcast(
      "chat:#{thread.organization_id}:thread:#{message.thread_id}",
      "new_message",
      %{
        id: message.id,
        thread_id: message.thread_id,
        sender_id: message.sender_id,
        body: message.body,
        message_type: message.message_type,
        inserted_at: message.inserted_at
      }
    )
  end

  defp notify_participants(thread, message) do
    thread.participants
    |> Enum.reject(&(&1.user_id == message.sender_id))
    |> Enum.reduce_while(:ok, fn participant, :ok ->
      case Notifications.dispatch_event(notification_type(message), %{
             user_id: participant.user_id,
             organization_id: thread.organization_id,
             dedupe_key: dedupe_key(message),
             thread_id: thread.id,
             context_type: thread.context_type,
             context_id: thread.context_id,
             message_id: message.id,
             sender_id: message.sender_id,
             body: String.slice(message.body, 0, 100),
             url: thread_url(thread, participant.user_id)
           }) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # ADR-144: someone who is not a member (yet) talks to the box from its
  # page, so their link opens that conversation there, not the gym's inbox.
  defp thread_url(%{context_type: :box, context_id: user_id} = thread, user_id) do
    if Organizations.membership_standing(thread.organization_id, user_id) == :member do
      "/messages?thread=#{thread.id}"
    else
      case Organizations.public_boxes([thread.organization_id]) do
        [%{slug: slug}] -> "/b/#{slug}/chat"
        _unpublished -> "/messages?thread=#{thread.id}"
      end
    end
  end

  defp thread_url(thread, _user_id), do: "/messages?thread=#{thread.id}"

  # Coaching messages and messages from the box reach the inbox; chat stays
  # in the chat.
  defp notification_type(%{message_type: type}) when type in [:coaching_message, :box_message],
    do: type

  defp notification_type(_message), do: :chat_message

  defp dedupe_key(%{message_type: type, id: id}) when type in [:coaching_message, :box_message],
    do: "#{type}:#{id}"

  defp dedupe_key(%{id: id}), do: "chat-message:#{id}"

  # «Τελευταία από τον coach» on the member's Box › Ο coach σου.
  defp invalidate_landing(thread, %{message_type: :coaching_message, sender_id: sender_id}) do
    thread.participants
    |> Enum.reject(&(&1.user_id == sender_id))
    |> Enum.map(& &1.user_id)
    |> InvalidateLandingPages.for_users()
  end

  defp invalidate_landing(_thread, _message), do: :ok

  # Staff-client communication analytics: direction comes from who is staff
  # in the gym (owners, admins, coaches, front desk...), not from the global
  # account role; member-to-member chat is not staff communication.
  defp record_analytics(message, thread) do
    staff = MapSet.new(Organizations.list_staff_user_ids(thread.organization_id))

    users =
      thread.participants
      |> Enum.map(& &1.user_id)
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1})

    sender_staff? = MapSet.member?(staff, message.sender_id)

    thread.participants
    |> Enum.reject(&(&1.user_id == message.sender_id))
    |> Enum.reduce_while(:ok, fn participant, :ok ->
      recipient_staff? = MapSet.member?(staff, participant.user_id)

      case direction(sender_staff?, recipient_staff?) do
        nil ->
          {:cont, :ok}

        direction ->
          attrs = %{
            "sender_id" => message.sender_id,
            "recipient_id" => participant.user_id,
            "thread_id" => thread.id,
            "sender_role_snapshot" => role_name(Map.get(users, message.sender_id)),
            "recipient_role_snapshot" => role_name(Map.get(users, participant.user_id)),
            "direction" => direction,
            "channel" => "in_app",
            "body" => message.body,
            "sent_at" => message.inserted_at,
            "context_type" => "messaging_#{thread.context_type}",
            "context_id" => thread.context_id || thread.id,
            "assigned_admin_id" =>
              if(sender_staff?, do: message.sender_id, else: participant.user_id),
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
      end
    end)
  end

  defp role_name(%{role: role}), do: to_string(role)
  defp role_name(_user), do: "unknown"

  defp direction(true, true), do: "admin_to_admin"
  defp direction(true, false), do: "admin_to_user"
  defp direction(false, true), do: "user_to_admin"
  defp direction(false, false), do: nil
end
