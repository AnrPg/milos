defmodule MilosTraining.Community.Queries.Feed do
  @moduledoc """
  One page of posts from a set of channels, newest first, keyset-paged
  (ADR-138). Hidden posts are shown only to their author and to staff of the
  gym that runs the club.
  """

  alias MilosTraining.Community.CommunityStore
  alias MilosTraining.Community.Domain.FeedCursor

  @default_limit 20
  @max_limit 50

  def page(context, %{channel_ids: channel_ids, viewer_id: viewer_id} = params) do
    limit = params |> Map.get(:limit) |> clamp()

    with {:ok, before} <- FeedCursor.decode(Map.get(params, :cursor)) do
      posts =
        CommunityStore.list_posts(context, %{
          channel_ids: channel_ids,
          viewer_id: viewer_id,
          moderated_organization_ids: Map.get(params, :moderated_organization_ids, []),
          author_id: Map.get(params, :author_id),
          before: before,
          limit: limit + 1
        })

      {page, rest} = Enum.split(posts, limit)

      {:ok,
       %{
         posts: page,
         next_cursor: if(rest != [] and page != [], do: FeedCursor.encode(List.last(page)))
       }}
    end
  end

  def pinned(context, channel_ids, viewer_id),
    do: CommunityStore.list_pinned_posts(context, channel_ids, viewer_id)

  defp clamp(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_limit)
  defp clamp(_limit), do: @default_limit
end
