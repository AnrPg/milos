defmodule Palee.Application.EventCards do
  @moduledoc """
  The event card on a club feed post (ADR-153, board 8): a post whose
  attachment is an event carries the event as the reader sees it now (date,
  place, going count, their own status, price) so «Θα έρθω» works inline.
  A weekly series has one card; it shows the next occurrence still ahead,
  or the last one once the run is over. A cancelled event shows as such.
  """

  alias Palee.Application.EventPresenter
  alias Palee.Community

  @doc "Puts `event` on every presented post (nil unless it carries an event)."
  def attach(posts, %{user_id: user_id}, clubs, now \\ DateTime.utc_now()) do
    wanted =
      posts
      |> Enum.filter(&(&1.attachment_type == "event" and is_binary(&1.attachment_id)))
      |> Enum.flat_map(fn post ->
        case Enum.find(clubs, &(&1.id == post.club[:id])) do
          nil -> []
          club -> [{club.organization_id, post.attachment_id}]
        end
      end)

    cards = cards(wanted, user_id, clubs, now)

    Enum.map(posts, fn post ->
      Map.put(
        post,
        :event,
        if(post.attachment_type == "event", do: Map.get(cards, post.attachment_id))
      )
    end)
  end

  defp cards([], _user_id, _clubs, _now), do: %{}

  defp cards(wanted, user_id, clubs, now) do
    shown =
      wanted
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {organization_id, ids} ->
        gym = %{organization_id: organization_id, user_id: user_id}

        gym
        |> Community.list_events(%{ids: ids, include_cancelled: true})
        |> Enum.map(&{&1.id, current(gym, &1, now)})
      end)

    presented =
      shown
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq_by(& &1.id)
      |> EventPresenter.present(EventPresenter.viewer(user_id, clubs), now: now)
      |> Map.new(&{&1.id, &1})

    Map.new(shown, fn {attached_id, event} -> {attached_id, Map.fetch!(presented, event.id)} end)
  end

  # A series card follows the run: the next live occurrence still ahead.
  defp current(_gym, %{series_id: nil} = event, _now), do: event

  defp current(gym, event, now) do
    if DateTime.compare(event.ends_at, now) == :gt do
      event
    else
      case Community.list_events(gym, %{series_id: event.series_id, from: now, limit: 1}) do
        [next] -> next
        [] -> event
      end
    end
  end
end
