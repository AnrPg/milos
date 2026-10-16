defmodule MilosTraining.Infrastructure.Community.EctoCommunityStore do
  @moduledoc "Ecto adapter for the Community context (ADR-138)."

  @behaviour MilosTraining.Community.Ports.CommunityStore

  import Ecto.Query

  alias MilosTraining.Community.{
    Channel,
    ChannelMembership,
    Club,
    ClubMembership,
    Post,
    PostComment,
    PostReaction
  }

  alias MilosTraining.Repo

  @builtin_conflict {:unsafe_fragment,
                     "(club_id, kind) WHERE kind IN ('announcements', 'wod', 'challenges')"}

  # Clubs and channels -------------------------------------------------------

  @impl true
  def ensure_gym_club(%{organization_id: organization_id}, channels) do
    Repo.transaction(fn ->
      club = gym_club(organization_id) || insert_gym_club(organization_id)

      Enum.each(channels, fn spec ->
        spec
        |> Map.merge(%{organization_id: organization_id, club_id: club.id})
        |> Channel.changeset()
        |> Repo.insert!(on_conflict: :nothing, conflict_target: @builtin_conflict)
      end)

      club_with_channels(club)
    end)
  end

  defp gym_club(organization_id),
    do: Repo.one(from c in Club, where: c.organization_id == ^organization_id and c.kind == "gym")

  defp insert_gym_club(organization_id) do
    %{organization_id: organization_id, kind: "gym", join_policy: "members_only"}
    |> Club.changeset()
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: {:unsafe_fragment, "(organization_id) WHERE kind = 'gym'"}
    )

    gym_club(organization_id)
  end

  @impl true
  def list_clubs(_context, []), do: []

  def list_clubs(_context, organization_ids) do
    clubs =
      Club
      |> where([c], c.organization_id in ^organization_ids and is_nil(c.archived_at))
      |> Repo.all()

    channels = channels_by_club(Enum.map(clubs, & &1.id))
    Enum.map(clubs, &normalize_club(&1, Map.get(channels, &1.id, [])))
  end

  @impl true
  def get_club(_context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Club{} = club <- Repo.get(Club, id) do
      club_with_channels(club)
    else
      _missing -> nil
    end
  end

  @impl true
  def get_channel(_context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Channel{} = channel <- Repo.get(Channel, id) do
      normalize_channel(channel)
    else
      _missing -> nil
    end
  end

  defp club_with_channels(club),
    do: normalize_club(club, Map.get(channels_by_club([club.id]), club.id, []))

  defp channels_by_club([]), do: %{}

  defp channels_by_club(club_ids) do
    Channel
    |> where([ch], ch.club_id in ^club_ids and is_nil(ch.archived_at))
    |> order_by([ch], asc: ch.position, asc: ch.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_channel/1)
    |> Enum.group_by(& &1.club_id)
  end

  @impl true
  def joined_channel_ids(_context, _user_id, []), do: []

  def joined_channel_ids(_context, user_id, channel_ids) do
    member_sources = ChannelMembership.member_sources()

    ChannelMembership
    |> where(
      [m],
      m.user_id == ^user_id and m.channel_id in ^channel_ids and m.source in ^member_sources
    )
    |> select([m], m.channel_id)
    |> Repo.all()
  end

  @impl true
  def suggested_channel_ids(_context, _user_id, []), do: []

  def suggested_channel_ids(_context, user_id, channel_ids) do
    ChannelMembership
    |> where(
      [m],
      m.user_id == ^user_id and m.channel_id in ^channel_ids and m.source == "suggested"
    )
    |> select([m], m.channel_id)
    |> Repo.all()
  end

  @impl true
  def join_channel(_context, channel, user_id, source) do
    %{
      organization_id: channel.organization_id,
      channel_id: channel.id,
      user_id: user_id,
      source: source
    }
    |> ChannelMembership.changeset()
    |> Repo.insert(
      on_conflict: [set: [source: source, updated_at: DateTime.utc_now()]],
      conflict_target: [:channel_id, :user_id]
    )
    |> case do
      {:ok, _membership} -> :ok
      error -> error
    end
  end

  # Leaving keeps a `dismissed` row so the channel is not suggested again.
  @impl true
  def leave_channel(context, channel, user_id),
    do: join_channel(context, channel, user_id, "dismissed")

  @impl true
  def ensure_context_channel(_context, club, spec) do
    attrs =
      Map.merge(spec, %{organization_id: club.organization_id, club_id: club.id, archived_at: nil})

    attrs
    |> Channel.changeset()
    |> Repo.insert(
      on_conflict: [set: [name: attrs.name, archived_at: nil, updated_at: DateTime.utc_now()]],
      conflict_target:
        {:unsafe_fragment, "(club_id, context_type, context_id) WHERE context_id IS NOT NULL"},
      returning: true
    )
    |> case do
      {:ok, channel} -> {:ok, normalize_channel(channel)}
      error -> error
    end
  end

  @impl true
  def archive_context_channels(_context, club_id, context_type, keep_context_ids) do
    now = DateTime.utc_now()

    Channel
    |> where(
      [ch],
      ch.club_id == ^club_id and ch.context_type == ^context_type and is_nil(ch.archived_at) and
        ch.context_id not in ^keep_context_ids
    )
    |> Repo.update_all(set: [archived_at: now, updated_at: now])

    :ok
  end

  # Offers a channel to members; never overrides a choice they already made.
  @impl true
  def suggest_channel_members(_context, []), do: :ok

  def suggest_channel_members(%{organization_id: organization_id}, pairs) do
    now = DateTime.utc_now()

    rows =
      Enum.map(pairs, fn {channel_id, user_id} ->
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          channel_id: channel_id,
          user_id: user_id,
          source: "suggested",
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ChannelMembership, rows,
      on_conflict: :nothing,
      conflict_target: [:channel_id, :user_id]
    )

    :ok
  end

  @impl true
  def notify_levels(_context, _user_id, []), do: %{}

  def notify_levels(_context, user_id, club_ids) do
    ClubMembership
    |> where([m], m.user_id == ^user_id and m.club_id in ^club_ids)
    |> select([m], {m.club_id, m.notify_level})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def put_notify_level(_context, club, user_id, level) do
    %{
      organization_id: club.organization_id,
      club_id: club.id,
      user_id: user_id,
      notify_level: level
    }
    |> ClubMembership.changeset()
    |> Repo.insert(
      on_conflict: [set: [notify_level: level, updated_at: DateTime.utc_now()]],
      conflict_target: [:club_id, :user_id]
    )
    |> case do
      {:ok, _membership} -> {:ok, level}
      error -> error
    end
  end

  # Posts --------------------------------------------------------------------

  @impl true
  def create_post(context, attrs) do
    attrs
    |> Post.changeset()
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        {:ok, get_post(context, post.id, post.author_id)}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :client_operation_id),
          do: replayed_post(context, attrs, changeset),
          else: {:error, changeset}
    end
  end

  # The outbox retried a post that already landed: answer with that post.
  defp replayed_post(context, attrs, changeset) do
    Post
    |> where(
      [p],
      p.author_id == ^attrs.author_id and p.client_operation_id == ^attrs.client_operation_id
    )
    |> select([p], p.id)
    |> Repo.one()
    |> case do
      nil -> {:error, changeset}
      id -> {:ok, get_post(context, id, attrs.author_id)}
    end
  end

  @impl true
  def get_post(_context, id, viewer_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Post
        |> where([p], p.id == ^id and is_nil(p.deleted_at))
        |> with_counts(viewer_id)
        |> Repo.one()

      :error ->
        nil
    end
  end

  @impl true
  def list_posts(_context, %{channel_ids: []}), do: []

  def list_posts(_context, filter) do
    viewer_id = filter.viewer_id

    Post
    |> where([p], p.channel_id in ^filter.channel_ids and is_nil(p.deleted_at))
    |> visible_to(viewer_id, Map.get(filter, :moderated_organization_ids, []))
    |> maybe_author(Map.get(filter, :author_id))
    |> before(Map.get(filter, :before))
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^filter.limit)
    |> with_counts(viewer_id)
    |> Repo.all()
  end

  @impl true
  def list_pinned_posts(_context, [], _viewer_id), do: []

  def list_pinned_posts(_context, channel_ids, viewer_id) do
    Post
    |> where(
      [p],
      p.channel_id in ^channel_ids and is_nil(p.deleted_at) and is_nil(p.hidden_at) and
        not is_nil(p.pinned_at)
    )
    |> order_by([p], desc: p.pinned_at)
    |> limit(10)
    |> with_counts(viewer_id)
    |> Repo.all()
  end

  defp visible_to(query, viewer_id, moderated_organization_ids) do
    where(
      query,
      [p],
      is_nil(p.hidden_at) or p.author_id == ^viewer_id or
        p.organization_id in ^moderated_organization_ids
    )
  end

  defp maybe_author(query, nil), do: query
  defp maybe_author(query, author_id), do: where(query, [p], p.author_id == ^author_id)

  defp before(query, nil), do: query

  defp before(query, {%DateTime{} = at, id}) do
    where(query, [p], p.inserted_at < ^at or (p.inserted_at == ^at and p.id < ^id))
  end

  defp with_counts(query, viewer_id) do
    select(query, [p], %{
      id: p.id,
      organization_id: p.organization_id,
      club_id: p.club_id,
      channel_id: p.channel_id,
      author_id: p.author_id,
      audience: p.audience,
      body: p.body,
      attachment_type: p.attachment_type,
      attachment_id: p.attachment_id,
      attachment: p.attachment,
      pinned_at: p.pinned_at,
      hidden_at: p.hidden_at,
      inserted_at: p.inserted_at,
      kudos_count:
        fragment(
          "(SELECT count(*) FROM community_post_reactions r WHERE r.post_id = ? AND r.kind = 'kudos')",
          p.id
        ),
      comment_count:
        fragment(
          "(SELECT count(*) FROM community_post_comments c WHERE c.post_id = ? AND c.deleted_at IS NULL)",
          p.id
        ),
      kudos_by_me:
        fragment(
          "EXISTS (SELECT 1 FROM community_post_reactions r WHERE r.post_id = ? AND r.kind = 'kudos' AND r.user_id = ?)",
          p.id,
          type(^viewer_id, :binary_id)
        )
    })
  end

  @impl true
  def moderate_post(context, id, attrs) do
    case Repo.get(Post, id) do
      nil ->
        {:error, :not_found}

      post ->
        with {:ok, post} <- post |> Post.moderation_changeset(attrs) |> Repo.update() do
          {:ok, get_post(context, post.id, post.author_id) || Map.from_struct(post)}
        end
    end
  end

  @impl true
  def react(_context, post, user_id, kind) do
    Repo.insert_all(
      PostReaction,
      [
        %{
          id: Ecto.UUID.generate(),
          organization_id: post.organization_id,
          post_id: post.id,
          user_id: user_id,
          kind: kind,
          inserted_at: DateTime.utc_now()
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:post_id, :user_id, :kind]
    )

    :ok
  end

  @impl true
  def unreact(_context, post, user_id, kind) do
    PostReaction
    |> where([r], r.post_id == ^post.id and r.user_id == ^user_id and r.kind == ^kind)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def list_comments(_context, post_id) do
    PostComment
    |> where([c], c.post_id == ^post_id and is_nil(c.deleted_at))
    |> order_by([c], asc: c.inserted_at, asc: c.id)
    |> Repo.all()
    |> Enum.map(&normalize_comment/1)
  end

  @impl true
  def get_comment(_context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %PostComment{deleted_at: nil} = comment <- Repo.get(PostComment, id) do
      normalize_comment(comment)
    else
      _missing -> nil
    end
  end

  @impl true
  def add_comment(_context, attrs) do
    attrs
    |> PostComment.changeset()
    |> Repo.insert()
    |> case do
      {:ok, comment} -> {:ok, normalize_comment(comment)}
      error -> error
    end
  end

  @impl true
  def delete_comment(_context, id, now) do
    PostComment
    |> where([c], c.id == ^id and is_nil(c.deleted_at))
    |> Repo.update_all(set: [deleted_at: now, updated_at: now])
    |> case do
      {1, _} -> :ok
      _none -> {:error, :not_found}
    end
  end

  # Normalisation ------------------------------------------------------------

  defp normalize_club(club, channels) do
    club
    |> Map.take([:id, :organization_id, :kind, :name, :join_policy, :archived_at])
    |> Map.put(:channels, channels)
  end

  defp normalize_channel(channel) do
    Map.take(channel, [
      :id,
      :organization_id,
      :club_id,
      :kind,
      :name,
      :write_policy,
      :membership,
      :context_type,
      :context_id,
      :position,
      :archived_at
    ])
  end

  defp normalize_comment(comment),
    do: Map.take(comment, [:id, :organization_id, :post_id, :author_id, :body, :inserted_at])
end
