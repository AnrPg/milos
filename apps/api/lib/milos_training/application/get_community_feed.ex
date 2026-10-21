defmodule MilosTraining.Application.GetCommunityFeed do
  @moduledoc """
  `GET /api/me/feed` (ADR-138, M7; ADR-142): «Τα clubs μου», newest first,
  read in the member's personal session across every gym they belong to.
  Without a filter it merges the channels that reach their feed, the
  profile posts of people they follow (and their own), and the public posts
  of boxes they follow but do not belong to. `club_id` narrows to one club
  (all its channels, pinned announcements first), `channel_id` to one
  channel, `mine` to their own posts (Εγώ › Αναρτήσεις).
  """

  alias MilosTraining.Application.{ClubScope, EventCards, PostPresenter}
  alias MilosTraining.{Community, Organizations}

  @default_limit 20
  @max_limit 50

  def call(%{user_id: user_id} = context, params) do
    limit = clamp(params[:limit])

    with {:ok, clubs} <- ClubScope.call(context),
         {:ok, channel_ids} <- channel_ids(clubs, params),
         {:ok, before} <- Community.decode_feed_cursor(params[:cursor]),
         {:ok, page} <-
           Community.feed_page(context, %{
             channel_ids: channel_ids,
             viewer_id: user_id,
             moderated_organization_ids: moderated(clubs),
             author_id: if(truthy?(params[:mine]), do: user_id),
             cursor: params[:cursor],
             limit: limit
           }) do
      pinned =
        if params[:cursor] in [nil, ""] and not truthy?(params[:mine]),
          do: Community.pinned_posts(context, channel_ids, user_id),
          else: []

      pinned_ids = MapSet.new(pinned, & &1.id)
      club_posts = Enum.reject(page.posts, &MapSet.member?(pinned_ids, &1.id))
      {profile_posts, box_posts, boxes} = beyond_clubs(context, clubs, params, before, limit)

      merged =
        (tag(club_posts, :club) ++ tag(profile_posts, :profile) ++ tag(box_posts, :box))
        |> Enum.sort_by(fn {_kind, post} -> {post.inserted_at, post.id} end, &newer?/2)

      {shown, rest} = Enum.split(merged, limit)
      more? = rest != [] or not is_nil(page.next_cursor)

      {:ok,
       %{
         pinned:
           pinned |> PostPresenter.posts(clubs, user_id) |> EventCards.attach(context, clubs),
         posts: shown |> present(clubs, boxes, user_id) |> EventCards.attach(context, clubs),
         next_cursor:
           if(more? and shown != [],
             do: shown |> List.last() |> elem(1) |> Community.encode_feed_cursor()
           )
       }}
    end
  end

  # Only the unfiltered feed and Εγώ (mine) reach past the member's clubs.
  defp beyond_clubs(%{user_id: user_id} = context, clubs, params, before, limit) do
    cond do
      is_binary(params[:club_id]) or is_binary(params[:channel_id]) ->
        {[], [], []}

      truthy?(params[:mine]) ->
        {profile_posts(context, [user_id], before, limit), [], []}

      true ->
        people = Community.followed_ids(context, user_id, "user")
        member_of = MapSet.new(clubs, & &1.organization_id)

        boxes =
          context
          |> Community.followed_ids(user_id, "organization")
          |> Enum.reject(&MapSet.member?(member_of, &1))
          |> Organizations.public_boxes()

        box_posts =
          Community.list_public_posts(
            context,
            Enum.map(boxes, & &1.organization_id),
            user_id,
            %{before: before, limit: limit + 1}
          )

        {profile_posts(context, [user_id | people], before, limit), box_posts, boxes}
    end
  end

  defp profile_posts(%{user_id: user_id} = context, author_ids, before, limit) do
    Community.list_profile_posts(context, %{
      author_ids: author_ids,
      viewer_id: user_id,
      before: before,
      limit: limit + 1
    })
  end

  defp tag(posts, kind), do: Enum.map(posts, &{kind, &1})

  defp newer?({at_a, id_a}, {at_b, id_b}) do
    case DateTime.compare(at_a, at_b) do
      :gt -> true
      :lt -> false
      :eq -> id_a >= id_b
    end
  end

  defp present(tagged, clubs, boxes, user_id) do
    by_kind = Enum.group_by(tagged, &elem(&1, 0), &elem(&1, 1))

    presented =
      (PostPresenter.posts(Map.get(by_kind, :club, []), clubs, user_id) ++
         PostPresenter.profile_posts(Map.get(by_kind, :profile, []), user_id) ++
         PostPresenter.public_box_posts(Map.get(by_kind, :box, []), boxes))
      |> Map.new(&{&1.id, &1})

    Enum.flat_map(tagged, fn {_kind, post} ->
      case Map.get(presented, post.id) do
        nil -> []
        shown -> [shown]
      end
    end)
  end

  defp clamp(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_limit)

  defp clamp(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} -> clamp(value)
      _invalid -> @default_limit
    end
  end

  defp clamp(_limit), do: @default_limit

  defp channel_ids(clubs, %{channel_id: channel_id}) when is_binary(channel_id) do
    with {:ok, _club, channel} <- ClubScope.find_channel(clubs, channel_id),
         do: {:ok, [channel.id]}
  end

  defp channel_ids(clubs, %{club_id: club_id}) when is_binary(club_id) do
    case Enum.find(clubs, &(&1.id == club_id)) do
      nil -> {:error, :not_found}
      club -> {:ok, Enum.map(club.channels, & &1.id)}
    end
  end

  defp channel_ids(clubs, params) do
    mine? = truthy?(params[:mine])

    ids = for club <- clubs, channel <- club.channels, mine? or channel.joined, do: channel.id
    {:ok, ids}
  end

  defp moderated(clubs),
    do: clubs |> Enum.filter(&Community.can_moderate?(&1.role)) |> Enum.map(& &1.organization_id)

  defp truthy?(value), do: value in [true, "true", "1"]
end
