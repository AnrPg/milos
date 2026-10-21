defmodule Palee.Application.PartnerRealtime do
  @moduledoc """
  Live updates for Partners (ADR-169 §7). A match's two people may belong to
  different gyms, so each change goes to both on their own user topic
  (`user:<user_id>`, as Buddy's, ADR-160) as one `partners:changed` event,
  through the `RealtimePublisher` port. The payload carries the kind and the
  match id only, never a message; clients refetch what they show.
  """

  require Logger

  alias Palee.Application.{BuddyRealtime, RealtimePublisher}

  @event "partners:changed"

  def event, do: @event

  def match_changed(match), do: publish(match, "partner_match_changed")
  def message_created(match), do: publish(match, "partner_message_created")
  def messages_read(match), do: publish(match, "partner_messages_read")

  defp publish(match, kind) do
    payload = %{kind: kind, match_id: match.id, club_id: match.club_id}

    [match.user_a_id, match.user_b_id]
    |> Enum.filter(&is_binary/1)
    |> Enum.each(fn user_id ->
      case RealtimePublisher.broadcast(BuddyRealtime.topic(user_id), @event, payload) do
        :ok -> :ok
        error -> Logger.warning("partners realtime #{kind} not published: #{inspect(error)}")
      end
    end)

    :ok
  end
end
