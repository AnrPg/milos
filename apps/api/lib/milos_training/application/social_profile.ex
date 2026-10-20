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
       requests_count: Community.count_incoming_follows(context, "user", user_id, "requested"),
       booking_sharing: booking_sharing(context, user_id),
       member_visibility: member_visibility(context, user_id)
     }}
  end

  @doc "Board 7 Q1: whether the member shows in their clubs' «Μέλη» (shown unless they hide)."
  def member_visibility(context, user_id) do
    settings = Community.social_settings(context, user_id)
    %{hidden: (settings && settings.hide_from_members) || false}
  end

  def set_member_visibility(%{user_id: user_id} = context, hidden) when is_boolean(hidden) do
    with {:ok, _settings} <-
           Community.put_social_settings(context, user_id, %{hide_from_members: hidden}),
         do: {:ok, member_visibility(context, user_id)}
  end

  @doc """
  Board 5 Q6: whether followers see the classes the member books (off until
  they say so) and whether the one-time offer was answered.
  """
  def booking_sharing(context, user_id) do
    settings = Community.social_settings(context, user_id)

    %{
      enabled: (settings && settings.share_bookings) || false,
      offered: not is_nil(settings && settings.share_bookings_offered_at)
    }
  end

  def set_booking_sharing(%{user_id: user_id} = context, enabled, now \\ DateTime.utc_now())
      when is_boolean(enabled) do
    with {:ok, _settings} <-
           Community.put_social_settings(context, user_id, %{
             share_bookings: enabled,
             share_bookings_offered_at: now
           }),
         do: {:ok, booking_sharing(context, user_id)}
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
