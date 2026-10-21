defmodule Palee.Application.SendMessage do
  @moduledoc """
  Sends a message as one of the three kinds a member receives (ADR-140 §6).

  * **Coaching message**: only a coach with an *active coaching
    relationship* to every client in the thread, whatever their role; always
    metered, one touchpoint per client. A coach's answer to a client's
    Ζητάω απάντηση is one even when the coach did not ask for it.
  * **Message from the box**: staff who may message for the gym
    (`message_from_box`) in the gym's thread with the member; not metered;
    optional topic.
  * **Chat**: everything else.
  """

  alias Palee.Application.TrackMessagingAnalytics
  alias Palee.{Coaching, Finance, Messaging, Organizations}

  def call(sender, params) do
    with {:ok, thread} <- Messaging.get_thread(params.thread_id, sender.id),
         {:ok, kind} <- kind(sender, thread, params) do
      deliver(kind, thread, sender, params)
    end
  end

  defp deliver({:coaching_message, clients}, _thread, _sender, params) do
    delivery_id = Map.get(params, :client_operation_id) || Ecto.UUID.generate()
    params = params |> Map.put(:message_type, :coaching_message) |> Map.delete(:topic)

    with {:ok, reservations} <- reserve_touchpoints(clients, delivery_id),
         {:ok, message} <- send_or_release(params, reservations, delivery_id) do
      TrackMessagingAnalytics.call({:ok, message})
    end
  end

  defp deliver(:box_message, _thread, _sender, params) do
    params
    |> Map.put(:message_type, :box_message)
    |> Messaging.send_message(%{reservations: []})
    |> TrackMessagingAnalytics.call()
  end

  defp deliver(:chat, _thread, _sender, params) do
    params
    |> Map.put(:message_type, :chat)
    |> Map.delete(:topic)
    |> Messaging.send_message(%{reservations: []})
    |> TrackMessagingAnalytics.call()
  end

  # The gym's thread with a member: staff write for the box, the member chats.
  defp kind(sender, %{context_type: :box} = thread, _params) do
    cond do
      thread.context_id == sender.id -> {:ok, :chat}
      may_message_from_box?(sender, thread) -> {:ok, :box_message}
      true -> {:error, :forbidden}
    end
  end

  defp kind(sender, thread, params) do
    requested = Map.get(params, :message_type)
    clients = other_participants(thread, sender.id)

    cond do
      requested == :box_message ->
        {:error, :box_message_outside_box_thread}

      requested == :coaching_message ->
        if coaches_all?(thread, sender.id, clients),
          do: {:ok, {:coaching_message, clients}},
          else: {:error, :no_coaching_relationship}

      answering_reply_request?(thread, sender.id) and coaches_all?(thread, sender.id, clients) ->
        {:ok, {:coaching_message, clients}}

      true ->
        {:ok, :chat}
    end
  end

  defp other_participants(thread, sender_id),
    do: thread.participants |> Enum.map(& &1.user_id) |> Enum.reject(&(&1 == sender_id))

  defp coaches_all?(_thread, _sender_id, []), do: false

  defp coaches_all?(thread, sender_id, clients) do
    context = %{organization_id: thread.organization_id}
    Enum.all?(clients, &Coaching.coaches?(context, sender_id, &1))
  end

  # The thread's latest message is a client's Ζητάω απάντηση (ADR-139 §7).
  defp answering_reply_request?(%{context_type: :direct} = thread, sender_id) do
    case Messaging.list_messages(thread.id, %{actor_id: sender_id, limit: 1}) do
      {:ok, [%{subject_id: subject_id, sender_id: author}]}
      when is_binary(subject_id) and author != sender_id ->
        true

      _other ->
        false
    end
  end

  defp answering_reply_request?(_thread, _sender_id), do: false

  defp may_message_from_box?(sender, thread) do
    case Organizations.resolve_tenant_context_by_id(sender, thread.organization_id) do
      {:ok, context} -> Organizations.can?(context, :message_from_box)
      _error -> false
    end
  end

  defp reserve_touchpoints(recipients, delivery_id) do
    Enum.reduce_while(recipients, {:ok, []}, fn recipient_id, {:ok, reservations} ->
      case Finance.reserve_entitlement(recipient_id, %{
             channel: :coach_messaging,
             capability: :receive_coaching_touchpoints,
             allowance: :coaching_touchpoints,
             quantity: 1,
             occurred_on: Date.utc_today(),
             source_context: "messaging",
             source_id: delivery_id,
             idempotency_key: "coach-check-in:#{delivery_id}:#{recipient_id}",
             metadata: %{"kind" => "coach_check_in"}
           }) do
        {:ok, reservation} ->
          {:cont, {:ok, [{recipient_id, reservation} | reservations]}}

        error ->
          release(reservations, "Coaching-message entitlement reservation failed")
          {:halt, error}
      end
    end)
  end

  defp send_or_release(params, reservations, delivery_id) do
    delivery = %{
      reservations:
        Enum.flat_map(reservations, fn
          {_recipient_id, %{id: nil}} ->
            []

          {recipient_id, %{id: reservation_id}} ->
            [
              %{
                recipient_id: recipient_id,
                reservation_id: reservation_id,
                delivery_id: delivery_id
              }
            ]
        end)
    }

    case Messaging.send_message(params, delivery) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        release(reservations, "Coaching message was not created")
        {:error, reason}
    end
  end

  defp release(reservations, reason) do
    Enum.each(reservations, fn
      {_recipient_id, %{id: nil}} ->
        :ok

      {_recipient_id, %{id: reservation_id}} ->
        Finance.release_entitlement(reservation_id, %{
          reason: reason,
          idempotency_key: "coach-check-in-release:#{reservation_id}"
        })
    end)

    :ok
  end
end
