defmodule Palee.Application.BuddyRealtime do
  @moduledoc """
  Live updates for Buddy για στήριξη (ADR-160). Buddy data is account-scoped,
  so each change goes to the people concerned on their own user topic
  (`user:<user_id>`, joined only with a token for that user) as one
  `buddy:changed` event, through the `RealtimePublisher` port.

  The payload carries only what changed and the ids to refetch: never a
  message, a reply's words or a phone number. Clients refetch what they show.

  Who hears what:

  - a request was sent, taken back or got the no-reply card: the sender's
    other devices (buddies hear nothing until the undo window closed);
  - a request was delivered: its buddies, and the sender;
  - a reply: the sender and the buddy who answered;
  - a conversation message or a read receipt: both people of the link;
  - a link was created, claimed, accepted, declined, stopped or changed:
    both people of the link.
  """

  require Logger

  alias Palee.Application.RealtimePublisher

  @event "buddy:changed"

  @doc "The topic a user's account-scoped live updates go to."
  def topic(user_id), do: "user:#{user_id}"

  def event, do: @event

  def request_sent(request),
    do: publish([request.user_id], "support_request_sent", request_ids(request))

  def request_undone(request),
    do: publish([request.user_id], "support_request_undone", request_ids(request))

  def request_delivered(request, buddy_ids),
    do: publish([request.user_id | buddy_ids], "support_request_delivered", request_ids(request))

  def request_nudged(request),
    do: publish([request.user_id], "support_request_nudged", request_ids(request))

  def reply_created(request, reply),
    do:
      publish(
        [request.user_id, reply.buddy_user_id],
        "support_reply_created",
        request |> request_ids() |> Map.put(:link_id, reply.link_id)
      )

  def message_created(link),
    do: publish(parties(link), "buddy_message_created", %{link_id: link.id})

  def messages_read(link), do: publish(parties(link), "buddy_messages_read", %{link_id: link.id})

  def link_changed(link), do: publish(parties(link), "buddy_link_changed", %{link_id: link.id})

  defp request_ids(request), do: %{request_id: request.id}

  defp parties(link), do: [link.user_id, Map.get(link, :buddy_user_id)]

  defp publish(user_ids, kind, ids) do
    payload = Map.put(ids, :kind, kind)

    user_ids
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.each(fn user_id ->
      case RealtimePublisher.broadcast(topic(user_id), @event, payload) do
        :ok -> :ok
        error -> Logger.warning("buddy realtime #{kind} not published: #{inspect(error)}")
      end
    end)

    :ok
  end
end
