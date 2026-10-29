defmodule Palee.Application.SocialProfile do
  @moduledoc """
  ADR-142 (P2-M2): the social side of a person. The member's own counts for
  Εγώ (posts, followers, following, waiting requests), and another person's
  profile as the viewer may see it: name, avatar, counts, both follow
  relationships and the profile posts the viewer may read, all of them or
  only those with photos or a video (ADR-231, the «Πολυμέσα» grid).
  """

  alias Palee.Application.PostPresenter
  alias Palee.{Community, Identity, Places}

  @page 20
  # Ten rows of the three-wide grid.
  @media_page 30

  def me(%{user_id: user_id} = context) do
    {:ok,
     %{
       posts_count: Community.count_profile_posts(context, user_id),
       media_count: Community.count_profile_posts(context, user_id, %{media_only: true}),
       followers_count: Community.count_incoming_follows(context, "user", user_id, "active"),
       following_count:
         Community.count_outgoing_follows(context, user_id, Community.follow_target_types(), [
           "active"
         ]),
       requests_count: Community.count_incoming_follows(context, "user", user_id, "requested"),
       booking_sharing: booking_sharing(context, user_id),
       member_visibility: member_visibility(context, user_id),
       around_visibility: around_visibility(context, user_id),
       privacy: privacy(context, user_id),
       follow_groups: Community.follow_groups(user_id)
     }}
  end

  @doc """
  ADR-193 §2 (amended 2026-10-25): «Ιδιωτικός λογαριασμός» (off until the
  member turns it on: a follow is then a request) and «Εμφάνιση στην
  αναζήτηση» (on). Public and searchable are the default.
  """
  def privacy(context, user_id) do
    settings = Community.social_settings(context, user_id)

    %{
      private_account: if(settings, do: settings.private_account, else: false),
      searchable: if(settings, do: settings.searchable, else: true)
    }
  end

  @doc "Going public accepts the requests waiting for the member (ADR-193 §2)."
  def set_privacy(%{user_id: user_id} = context, attrs, now \\ DateTime.utc_now()) do
    changes =
      attrs
      |> Map.take([:private_account, :searchable])
      |> Enum.filter(fn {_key, value} -> is_boolean(value) end)
      |> Map.new()

    with true <- changes != %{} || {:error, :bad_request},
         {:ok, _settings} <- Community.put_social_settings(context, user_id, changes) do
      if changes[:private_account] == false,
        do: Community.accept_all_follow_requests(context, now)

      {:ok, privacy(context, user_id)}
    end
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
  ADR-154: «Φαίνομαι στο Γύρω μου», off until the member turns it on. Their
  public posts then show in Γύρω μου at the centroid of their main
  neighbourhood, so it only works once «Η περιοχή μου» is set.
  """
  def around_visibility(context, user_id) do
    settings = Community.social_settings(context, user_id)

    %{
      visible: (settings && settings.visible_around) || false,
      has_area: Places.home_area(%{user_id: user_id}) != []
    }
  end

  def set_around_visibility(%{user_id: user_id} = context, visible) when is_boolean(visible) do
    with {:ok, _settings} <-
           Community.put_social_settings(context, user_id, %{visible_around: visible}),
         do: {:ok, around_visibility(context, user_id)}
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
    with {:ok, person} <- find(person_id, viewer_id) do
      followers = Community.follower_counts("user", [person.id])
      my_status = Community.follow_status(context, "user", person.id)
      follows_me = follows_me(context, person.id, viewer_id)

      {:ok,
       %{
         id: person.id,
         nickname: person.nickname,
         handle: Map.get(person, :handle),
         avatar_url: Map.get(person, :avatar_url),
         is_me: person.id == viewer_id,
         private: Community.public_user_ids([person.id]) == [],
         followers_count: Map.get(followers, person.id, 0),
         following_count: Community.following_count(person.id),
         follow_groups: Community.follow_groups(person.id),
         my_status: my_status,
         follows_me: follows_me,
         buddy: Community.buddies?(my_status, if(follows_me, do: "active", else: "none"))
       }}
    end
  end

  @doc "The person's profile posts the viewer may read, newest first."
  def posts(context, person_id, params), do: page(context, person_id, params, @page, false)

  @doc """
  ADR-231: the posts behind the profile's «Πολυμέσα» grid, those with photos
  or a video, newest first. The same audience rules as `posts/3` decide what
  the viewer reads (RLS), so a private account's grid stays locked too.
  """
  def media(context, person_id, params),
    do: page(context, person_id, params, @media_page, true)

  defp page(%{user_id: viewer_id} = context, person_id, params, size, media_only) do
    with {:ok, person} <- find(person_id, viewer_id),
         {:ok, before} <- Community.decode_feed_cursor(params[:cursor] || params["cursor"]) do
      posts =
        Community.list_profile_posts(context, %{
          author_ids: [person.id],
          viewer_id: viewer_id,
          media_only: media_only,
          before: before,
          limit: size + 1
        })

      {page, rest} = Enum.split(posts, size)

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

  # ADR-184: a mock person is a 404 for everyone but its demo business's staff.
  defp find(id, viewer_id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{id: _} = person <- Identity.find_by_id(id),
         true <- Identity.visible_to?(person.id, viewer_id) do
      {:ok, person}
    else
      _missing -> {:error, :not_found}
    end
  end
end
