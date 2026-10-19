defmodule MilosTraining.Application.SocialProfile do
  @moduledoc """
  ADR-142 (P2-M2): the social side of a person. The member's own counts for
  Εγώ (posts, followers, following, waiting requests), and another person's
  profile as the viewer may see it: name, avatar, counts, both follow
  relationships and the profile posts the viewer may read.
  """

  alias MilosTraining.Application.PostPresenter
  alias MilosTraining.{Community, Identity}

  @page 20

  def me(%{user_id: user_id} = context) do
    {:ok,
     %{
       posts_count: Community.count_profile_posts(context, user_id),
       followers_count: Community.count_incoming_follows(context, "user", user_id, "active"),
       following_count:
         Community.count_outgoing_follows(context, user_id, Community.follow_target_types(), [
           "active"
         ]),
       requests_count: Community.count_incoming_follows(context, "user", user_id, "requested")
     }}
  end

  def person(%{user_id: viewer_id} = context, person_id) do
    with {:ok, person} <- find(person_id) do
      followers = Community.follower_counts("user", [person.id])

      {:ok,
       %{
         id: person.id,
         nickname: person.nickname,
         avatar_url: Map.get(person, :avatar_url),
         is_me: person.id == viewer_id,
         followers_count: Map.get(followers, person.id, 0),
         following_count: Community.following_count(person.id),
         my_status: Community.follow_status(context, "user", person.id),
         follows_me: follows_me(context, person.id, viewer_id)
       }}
    end
  end

  @doc "The person's profile posts the viewer may read, newest first."
  def posts(%{user_id: viewer_id} = context, person_id, params) do
    with {:ok, person} <- find(person_id),
         {:ok, before} <- Community.decode_feed_cursor(params[:cursor] || params["cursor"]) do
      posts =
        Community.list_profile_posts(context, %{
          author_ids: [person.id],
          viewer_id: viewer_id,
          before: before,
          limit: @page + 1
        })

      {page, rest} = Enum.split(posts, @page)

      {:ok,
       %{
         posts: PostPresenter.profile_posts(page, viewer_id),
         next_cursor:
           if(rest != [] and page != [], do: Community.encode_feed_cursor(List.last(page)))
       }}
    end
  end

  # The viewer reads the follows that target them.
  defp follows_me(_context, person_id, person_id), do: false

  defp follows_me(context, person_id, viewer_id),
    do: match?(%{status: "active"}, Community.get_follow(context, person_id, "user", viewer_id))

  defp find(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{id: _} = person <- Identity.find_by_id(id) do
      {:ok, person}
    else
      _missing -> {:error, :not_found}
    end
  end
end
