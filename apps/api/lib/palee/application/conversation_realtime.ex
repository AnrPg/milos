defmodule Palee.Application.ConversationRealtime do
  @moduledoc """
  Live updates for person conversations (ADR-193 §3). They are
  account-scoped, so each change goes to both people on their own user topic
  (`user:<user_id>`) as one `conversation:changed` event carrying ids only,
  never a message's words. Clients refetch what they show.
  """

  require Logger

  alias Palee.Application.RealtimePublisher

  @event "conversation:changed"

  def event, do: @event

  def message_created(conversation, message),
    do: publish(conversation, "message_created", %{message_id: message.id})

  def read(conversation), do: publish(conversation, "read", %{})
  def folder_changed(conversation), do: publish(conversation, "folder_changed", %{})

  defp publish(conversation, kind, ids) do
    payload = ids |> Map.put(:conversation_id, conversation.id) |> Map.put(:kind, kind)

    for user_id <- [conversation.user_a_id, conversation.user_b_id] do
      case RealtimePublisher.broadcast("user:#{user_id}", @event, payload) do
        :ok -> :ok
        error -> Logger.warning("conversation realtime #{kind} not published: #{inspect(error)}")
      end
    end

    :ok
  end
end
