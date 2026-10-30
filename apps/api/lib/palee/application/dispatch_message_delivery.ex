defmodule Palee.Application.DispatchMessageDelivery do
  alias Palee.Application.{
    BoxInbox,
    InvalidateLandingPages,
    RealtimePublisher,
    RecordCommunicationMessage
  }

  alias Palee.{Finance, Identity, Messaging, Notifications, Organizations}
  alias Palee.Messaging.Domain.BoxInboxPolicy

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

  # ADR-282: a box thread tells the box's inbox about the person's message
  # (whoever answered last, else everyone in it) and the person about the
  # box's answer.
  defp notify_participants(%{context_type: :box} = thread, message) do
    recent = recent_messages(thread, message)

    thread
    |> BoxInboxPolicy.recipients(
      message.sender_id,
      BoxInboxPolicy.handler(thread, Enum.drop(recent, 1)),
      BoxInbox.audience(thread)
    )
    |> Enum.reduce_while(:ok, fn user_id, :ok ->
      case notify_box_recipient(thread, message, user_id) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
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

  @doc "«Φέρε τον coach»: the coach hears they were brought into the person's thread."
  def notify_coach_brought_in(%{context_type: :box} = thread, coach_id, brought_by_id) do
    last =
      case Messaging.list_messages(thread.id, %{actor_id: brought_by_id, limit: 1}) do
        {:ok, [message]} -> message
        _none -> nil
      end

    Notifications.dispatch_event(
      :box_inbox_message,
      box_inbox_payload(thread, last, coach_id)
      |> Map.merge(%{
        dedupe_key: "box_inbox_coach:#{thread.id}:#{coach_id}:#{last && last.id}",
        brought_in_by: nickname(brought_by_id)
      })
    )
  end

  defp notify_box_recipient(%{context_id: person_id} = thread, message, person_id) do
    Notifications.dispatch_event(notification_type(message), %{
      user_id: person_id,
      organization_id: thread.organization_id,
      dedupe_key: dedupe_key(message),
      thread_id: thread.id,
      context_type: thread.context_type,
      context_id: thread.context_id,
      message_id: message.id,
      sender_id: message.sender_id,
      body: String.slice(message.body, 0, 100),
      url: person_url(thread)
    })
  end

  defp notify_box_recipient(thread, message, user_id) do
    Notifications.dispatch_event(
      :box_inbox_message,
      box_inbox_payload(thread, message, user_id)
      |> Map.put(:dedupe_key, "box_inbox_message:#{message.id}:#{user_id}")
    )
  end

  defp box_inbox_payload(thread, message, user_id) do
    %{
      user_id: user_id,
      organization_id: thread.organization_id,
      thread_id: thread.id,
      context_type: thread.context_type,
      context_id: thread.context_id,
      message_id: message && message.id,
      sender_id: thread.context_id,
      sender_nickname: nickname(thread.context_id),
      box_name: box_name(thread.organization_id),
      topic: message && message.topic,
      body: message && String.slice(message.body, 0, 100),
      url: "/messages?filter=clubs&thread=#{thread.id}"
    }
  end

  defp nickname(user_id) do
    case Identity.list_by_ids([user_id]) do
      [%{nickname: nickname}] -> nickname
      _missing -> nil
    end
  end

  # The newest messages, the one being delivered first.
  defp recent_messages(thread, message) do
    case Messaging.list_messages(thread.id, %{actor_id: message.sender_id, limit: 50}) do
      {:ok, messages} -> messages
      _error -> [message]
    end
  end

  # ADR-282: the person reads their thread with a box on its chat screen,
  # members and newcomers alike (it works for unpublished boxes too).
  defp person_url(%{organization_id: organization_id} = thread) do
    case Organizations.brand_summary(organization_id) do
      %{slug: slug} when is_binary(slug) -> "/b/#{slug}/chat"
      _missing -> "/messages?thread=#{thread.id}"
    end
  end

  defp box_name(organization_id) do
    case Organizations.brand_summary(organization_id) do
      %{name: name} -> name
      _missing -> nil
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
