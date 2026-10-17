defmodule MilosTraining.Application.GetCommunityFeed do
  @moduledoc """
  `GET /api/me/feed` (ADR-138, M7): posts from the member's clubs, newest
  first, read in their personal session across every gym they belong to.
  Without a filter it lists the channels that reach their feed; `club_id`
  narrows to one club (all its channels, pinned announcements first),
  `channel_id` to one channel, `mine` to their own posts (Εγώ › Αναρτήσεις).
  """

  alias MilosTraining.Application.{ClubScope, PostPresenter}
  alias MilosTraining.Community

  def call(%{user_id: user_id} = context, params) do
    with {:ok, clubs} <- ClubScope.call(context),
         {:ok, channel_ids} <- channel_ids(clubs, params),
         {:ok, page} <-
           Community.feed_page(context, %{
             channel_ids: channel_ids,
             viewer_id: user_id,
             moderated_organization_ids: moderated(clubs),
             author_id: if(truthy?(params[:mine]), do: user_id),
             cursor: params[:cursor],
             limit: params[:limit]
           }) do
      pinned =
        if params[:cursor] in [nil, ""] and not truthy?(params[:mine]),
          do: Community.pinned_posts(context, channel_ids, user_id),
          else: []

      pinned_ids = MapSet.new(pinned, & &1.id)

      {:ok,
       %{
         pinned: PostPresenter.posts(pinned, clubs, user_id),
         posts:
           page.posts
           |> Enum.reject(&MapSet.member?(pinned_ids, &1.id))
           |> PostPresenter.posts(clubs, user_id),
         next_cursor: page.next_cursor
       }}
    end
  end

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
