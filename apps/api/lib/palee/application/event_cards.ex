defmodule Palee.Application.EventCards do
  @moduledoc """
  The event card on a feed post (ADR-153, board 8): a post whose attachment
  is an event carries the event as the reader sees it now (date, place,
  going count, their own status, price) so «Θα έρθω» works inline.
  A weekly series has one card; it shows the next occurrence still ahead,
  or the last one once the run is over. A cancelled event shows as such.

  ADR-185: a card can name the event's organisation in its snapshot
  (`organization_id`): a person's own event on their profile post, or an
  event a box co-hosts on that box's announcements. A co-host's card shows
  the event only while the box still co-hosts it; a profile card only to
  people who may see the event (and it is dropped otherwise).
  """

  alias Palee.Application.EventPresenter
  alias Palee.Community

  @doc "Puts `event` on every presented post (nil unless it carries an event)."
  def attach(posts, %{user_id: user_id}, clubs, now \\ DateTime.utc_now()) do
    wanted =
      posts
      |> Enum.filter(&(&1.attachment_type == "event" and is_binary(&1.attachment_id)))
      |> Enum.flat_map(&wanted(&1, clubs))

    cohosting = cohosting(wanted, user_id)
    viewer = EventPresenter.viewer(user_id, clubs)
    cards = cards(Enum.uniq(Enum.map(wanted, &elem(&1, 0))), viewer, now)

    Enum.flat_map(posts, fn post ->
      found = if post.attachment_type == "event", do: card(post, wanted, cohosting, cards)

      cond do
        post.attachment_type != "event" ->
          [Map.put(post, :event, nil)]

        post[:origin] == "profile" ->
          case found do
            {raw, shown} ->
              if EventPresenter.visible?(raw, viewer),
                do: [Map.put(post, :event, shown)],
                else: []

            nil ->
              []
          end

        true ->
          [Map.put(post, :event, found && elem(found, 1))]
      end
    end)
  end

  # `{{organization_id, event_id}, post_id, post_organization_id}` for every
  # card to fill: the snapshot's organisation, else the club's.
  defp wanted(post, clubs) do
    club = post[:club] && Enum.find(clubs, &(&1.id == post.club[:id]))
    snapshot_org = post.attachment && post.attachment["organization_id"]
    post_org = club && club.organization_id

    case snapshot_org || post_org do
      nil -> []
      organization_id -> [{{organization_id, post.attachment_id}, post.id, post_org}]
    end
  end

  # Which cross-organisation cards are still co-hosted by the post's box.
  defp cohosting(wanted, user_id) do
    crossing =
      for {{org, event_id}, _post_id, post_org} <- wanted,
          is_binary(post_org),
          org != post_org,
          do: event_id

    case crossing do
      [] ->
        MapSet.new()

      ids ->
        %{user_id: user_id}
        |> Community.accepted_event_cohosts(Enum.uniq(ids), nil)
        |> MapSet.new(&{&1.event_id, &1.cohost_organization_id})
    end
  end

  defp card(post, wanted, cohosting, cards) do
    case Enum.find(wanted, &(elem(&1, 1) == post.id)) do
      nil ->
        nil

      {{org, event_id}, _post_id, post_org} ->
        if is_binary(post_org) and org != post_org and
             not MapSet.member?(cohosting, {event_id, post_org}),
           do: nil,
           else: Map.get(cards, event_id)
    end
  end

  defp cards([], _viewer, _now), do: %{}

  defp cards(wanted, viewer, now) do
    shown =
      wanted
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {organization_id, ids} ->
        gym = %{organization_id: organization_id, user_id: viewer.user_id}

        gym
        |> Community.list_events(%{ids: ids, include_cancelled: true})
        |> Enum.map(&{&1.id, current(gym, &1, now)})
      end)

    presented =
      shown
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq_by(& &1.id)
      |> EventPresenter.present(viewer, now: now)
      |> Map.new(&{&1.id, &1})

    Map.new(shown, fn {attached_id, event} ->
      {attached_id, {event, Map.fetch!(presented, event.id)}}
    end)
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
