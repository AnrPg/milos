defmodule MilosTraining.Infrastructure.Community.EctoCommunityStore do
  @moduledoc "Ecto adapter for the Community context (ADR-138, ADR-143)."

  @behaviour MilosTraining.Community.Ports.CommunityStore

  import Ecto.Query

  alias MilosTraining.Community.{
    Channel,
    ChannelMembership,
    Club,
    ClubMembership,
    CommunitySettings,
    Post,
    PostComment,
    PostReaction,
    Report
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

  # Open clubs (ADR-143) -----------------------------------------------------

  @impl true
  def create_club(%{organization_id: organization_id}, attrs, channels) do
    Repo.transaction(fn ->
      club =
        attrs
        |> Map.merge(%{organization_id: organization_id, kind: "open"})
        |> Club.changeset()
        |> Repo.insert()
        |> case do
          {:ok, club} -> club
          {:error, changeset} -> Repo.rollback(changeset)
        end

      Enum.each(channels, fn spec ->
        spec
        |> Map.merge(%{organization_id: organization_id, club_id: club.id})
        |> Channel.changeset()
        |> Repo.insert!()
      end)

      club_with_channels(club)
    end)
  end

  @impl true
  def update_club(_context, id, attrs) do
    with %Club{} = club <- Repo.get(Club, id) || {:error, :not_found},
         {:ok, club} <- club |> Club.changeset(attrs) |> Repo.update() do
      {:ok, club_with_channels(club)}
    end
  end

  @impl true
  def list_clubs_by_ids(_context, []), do: []

  def list_clubs_by_ids(_context, ids) do
    clubs = Club |> where([c], c.id in ^ids and is_nil(c.archived_at)) |> Repo.all()
    channels = channels_by_club(Enum.map(clubs, & &1.id))
    Enum.map(clubs, &normalize_club(&1, Map.get(channels, &1.id, [])))
  end

  # Live open clubs anyone signed in can find; `organization_ids` narrows to
  # some gyms, `query` matches the name.
  @impl true
  def list_open_clubs(_context, filter) do
    Club
    |> where([c], c.kind == "open" and is_nil(c.archived_at))
    |> then(fn query ->
      case Map.get(filter, :organization_ids) do
        nil -> query
        ids -> where(query, [c], c.organization_id in ^ids)
      end
    end)
    |> then(fn query ->
      case Map.get(filter, :query) do
        text when is_binary(text) and text != "" ->
          where(query, [c], ilike(c.name, ^"%#{escape_like(text)}%"))

        _none ->
          query
      end
    end)
    |> order_by([c], asc: c.name)
    |> limit(^Map.get(filter, :limit, 50))
    |> Repo.all()
    |> Enum.map(&normalize_club(&1, []))
  end

  @impl true
  def open_club_member_counts(_context, []), do: %{}

  def open_club_member_counts(_context, ids) do
    binary_ids = Enum.map(ids, &Ecto.UUID.dump!/1)

    Repo
    |> Ecto.Adapters.SQL.query!(
      "SELECT club_id, member_count FROM milos_open_club_member_counts($1)",
      [binary_ids]
    )
    |> Map.get(:rows)
    |> Map.new(fn [club_id, count] -> {Ecto.UUID.cast!(club_id), count} end)
  end

  @impl true
  def club_memberships_of(_context, user_id) do
    ClubMembership
    |> join(:inner, [m], c in Club, on: c.id == m.club_id)
    |> where([m, c], m.user_id == ^user_id and c.kind == "open" and is_nil(c.archived_at))
    |> select([m, c], %{
      club_id: m.club_id,
      organization_id: m.organization_id,
      status: m.status,
      notify_level: m.notify_level
    })
    |> Repo.all()
  end

  @impl true
  def list_club_memberships(_context, club_id, status) do
    ClubMembership
    |> where([m], m.club_id == ^club_id)
    |> then(fn query -> if status, do: where(query, [m], m.status == ^status), else: query end)
    |> order_by([m], asc: m.inserted_at)
    |> select([m], %{user_id: m.user_id, status: m.status, inserted_at: m.inserted_at})
    |> Repo.all()
  end

  @impl true
  def get_club_membership(_context, club_id, user_id) do
    ClubMembership
    |> where([m], m.club_id == ^club_id and m.user_id == ^user_id)
    |> select([m], %{user_id: m.user_id, status: m.status, notify_level: m.notify_level})
    |> Repo.one()
  end

  @impl true
  def put_club_membership(_context, club, user_id, attrs) do
    now = DateTime.utc_now()
    set = attrs |> Map.take([:status, :notify_level]) |> Map.put(:updated_at, now)

    %{organization_id: club.organization_id, club_id: club.id, user_id: user_id}
    |> Map.merge(attrs)
    |> ClubMembership.changeset()
    |> Repo.insert(
      on_conflict: [set: Map.to_list(set)],
      conflict_target: [:club_id, :user_id],
      returning: true
    )
    |> case do
      {:ok, membership} ->
        {:ok, Map.take(membership, [:user_id, :status, :notify_level])}

      error ->
        error
    end
  end

  @impl true
  def delete_club_membership(_context, club_id, user_id) do
    ClubMembership
    |> where([m], m.club_id == ^club_id and m.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  # Member groups (ADR-143) --------------------------------------------------

  @impl true
  def get_community_settings(_context) do
    case Repo.one(CommunitySettings) do
      nil -> CommunitySettings.defaults()
      settings -> Map.take(settings, CommunitySettings.fields())
    end
  end

  @impl true
  def put_community_settings(%{organization_id: organization_id}, attrs) do
    # Only the fields given change: the others keep what the gym chose.
    changed = Map.keys(Map.take(attrs, CommunitySettings.fields()))

    attrs
    |> Map.put(:organization_id, organization_id)
    |> CommunitySettings.changeset()
    |> Repo.insert(
      on_conflict: {:replace, changed ++ [:updated_at]},
      conflict_target: [:organization_id],
      returning: true
    )
    |> case do
      {:ok, settings} -> {:ok, Map.take(settings, CommunitySettings.fields())}
      error -> error
    end
  end

  @impl true
  def create_group(_context, club, spec, creator_id, status) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()

      channel =
        spec
        |> Map.merge(%{
          organization_id: club.organization_id,
          club_id: club.id,
          created_by_id: creator_id,
          status: status
        })
        |> Channel.changeset()
        |> Ecto.Changeset.put_change(:decided_at, if(status == "active", do: now))
        |> Repo.insert()
        |> case do
          {:ok, channel} -> channel
          {:error, changeset} -> Repo.rollback(changeset)
        end

      %{
        organization_id: club.organization_id,
        channel_id: channel.id,
        user_id: creator_id,
        source: "auto",
        role: "admin"
      }
      |> ChannelMembership.changeset()
      |> Repo.insert!()

      normalize_channel(channel)
    end)
  end

  @impl true
  def list_groups(_context, club_id, filter) do
    member_sources = ChannelMembership.member_sources()
    statuses = Map.get(filter, :statuses, ["active"])

    Channel
    |> where([ch], ch.club_id == ^club_id and ch.kind == "member_group")
    |> where([ch], ch.status in ^statuses)
    |> then(fn query ->
      if Map.get(filter, :archived, false),
        do: where(query, [ch], not is_nil(ch.archived_at)),
        else: where(query, [ch], is_nil(ch.archived_at))
    end)
    |> order_by([ch], desc: ch.last_post_at, asc: ch.name)
    |> select([ch], %{
      channel: ch,
      member_count:
        fragment(
          "(SELECT count(*) FROM community_channel_memberships m WHERE m.channel_id = ? AND m.source = ANY(?))",
          ch.id,
          ^member_sources
        ),
      request_count:
        fragment(
          "(SELECT count(*) FROM community_channel_memberships m WHERE m.channel_id = ? AND m.source = 'requested')",
          ch.id
        )
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      row.channel
      |> normalize_channel()
      |> Map.merge(%{member_count: row.member_count, request_count: row.request_count})
    end)
  end

  @impl true
  def update_group(_context, id, attrs) do
    with %Channel{kind: "member_group"} = channel <-
           Repo.get(Channel, id) || {:error, :not_found},
         {:ok, channel} <- channel |> Channel.group_changeset(attrs) |> Repo.update() do
      {:ok, normalize_channel(channel)}
    else
      %Channel{} -> {:error, :not_found}
      error -> error
    end
  end

  @impl true
  def update_group_lifecycle(_context, id, attrs) do
    with %Channel{kind: "member_group"} = channel <-
           Repo.get(Channel, id) || {:error, :not_found},
         {:ok, channel} <- channel |> Channel.lifecycle_changeset(attrs) |> Repo.update() do
      {:ok, normalize_channel(channel)}
    else
      %Channel{} -> {:error, :not_found}
      error -> error
    end
  end

  @impl true
  def channel_memberships_of(_context, _user_id, []), do: %{}

  def channel_memberships_of(_context, user_id, channel_ids) do
    ChannelMembership
    |> where([m], m.user_id == ^user_id and m.channel_id in ^channel_ids)
    |> select([m], {m.channel_id, %{source: m.source, role: m.role}})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def list_channel_memberships(_context, channel_id) do
    sources = ["requested", "pending_invite" | ChannelMembership.member_sources()]

    ChannelMembership
    |> where([m], m.channel_id == ^channel_id and m.source in ^sources)
    |> order_by([m], desc: m.role, asc: m.inserted_at)
    |> select([m], %{user_id: m.user_id, source: m.source, role: m.role, since: m.inserted_at})
    |> Repo.all()
  end

  @impl true
  def put_channel_membership(_context, channel, user_id, attrs) do
    source = Map.fetch!(attrs, :source)
    role = Map.get(attrs, :role, "member")

    %{
      organization_id: channel.organization_id,
      channel_id: channel.id,
      user_id: user_id,
      source: source,
      role: role
    }
    |> ChannelMembership.changeset()
    |> Repo.insert(
      on_conflict: [set: [source: source, role: role, updated_at: DateTime.utc_now()]],
      conflict_target: [:channel_id, :user_id]
    )
    |> case do
      {:ok, _membership} -> :ok
      error -> error
    end
  end

  @impl true
  def quiet_groups(_context, cutoff) do
    Channel
    |> where([ch], ch.kind == "member_group" and ch.status == "active" and is_nil(ch.archived_at))
    |> where(
      [ch],
      fragment("coalesce(?, ?, ?)", ch.last_post_at, ch.decided_at, ch.inserted_at) < ^cutoff
    )
    |> Repo.all()
    |> Enum.map(&normalize_channel/1)
  end

  # PT squads (ADR-168) -------------------------------------------------------

  @impl true
  def list_squads(_context, club_id, filter) do
    member_sources = ChannelMembership.member_sources()

    Channel
    |> where([ch], ch.club_id == ^club_id and ch.kind == "pt_squad")
    |> then(fn query ->
      if Map.get(filter, :archived, false),
        do: where(query, [ch], not is_nil(ch.archived_at)),
        else: where(query, [ch], is_nil(ch.archived_at))
    end)
    |> then(fn query ->
      case filter do
        %{coach_id: coach_id} -> where(query, [ch], ch.created_by_id == ^coach_id)
        _all -> query
      end
    end)
    |> then(fn query ->
      case filter do
        %{ids: ids} -> where(query, [ch], ch.id in ^ids)
        _all -> query
      end
    end)
    |> order_by([ch], asc: fragment("lower(?)", ch.name), asc: ch.inserted_at)
    |> select([ch], %{
      channel: ch,
      member_count:
        fragment(
          "(SELECT count(*) FROM community_channel_memberships m WHERE m.channel_id = ? AND m.source = ANY(?) AND m.user_id <> ?)",
          ch.id,
          ^member_sources,
          ch.created_by_id
        ),
      invite_count:
        fragment(
          "(SELECT count(*) FROM community_channel_memberships m WHERE m.channel_id = ? AND m.source = 'pending_invite')",
          ch.id
        )
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      row.channel
      |> normalize_channel()
      |> Map.merge(%{member_count: row.member_count, invite_count: row.invite_count})
    end)
  end

  @impl true
  def squad_memberships_of(_context, user_id) do
    ChannelMembership
    |> join(:inner, [m], ch in Channel, on: ch.id == m.channel_id)
    |> where([m, ch], m.user_id == ^user_id and ch.kind == "pt_squad" and is_nil(ch.archived_at))
    |> where([m], m.source != "dismissed")
    |> select([m, ch], %{
      channel_id: m.channel_id,
      club_id: ch.club_id,
      coach_id: ch.created_by_id,
      source: m.source,
      role: m.role,
      since: m.updated_at
    })
    |> Repo.all()
  end

  @impl true
  def update_squad(_context, id, attrs) do
    with %Channel{kind: "pt_squad"} = channel <- Repo.get(Channel, id) || {:error, :not_found},
         {:ok, channel} <- channel |> Channel.squad_changeset(attrs) |> Repo.update() do
      {:ok, normalize_channel(channel)}
    else
      %Channel{} -> {:error, :not_found}
      error -> error
    end
  end

  @impl true
  def set_squad_archived(_context, id, archived_at) do
    with %Channel{kind: "pt_squad"} = channel <- Repo.get(Channel, id) || {:error, :not_found},
         {:ok, channel} <-
           channel |> Channel.lifecycle_changeset(%{archived_at: archived_at}) |> Repo.update() do
      {:ok, normalize_channel(channel)}
    else
      %Channel{} -> {:error, :not_found}
      error -> error
    end
  end

  @impl true
  def dismiss_from_coach_squads(_context, coach_id, user_id) do
    squad_ids =
      Channel
      |> where([ch], ch.kind == "pt_squad" and ch.created_by_id == ^coach_id)
      |> select([ch], ch.id)

    {count, _rows} =
      ChannelMembership
      |> where([m], m.user_id == ^user_id and m.channel_id in subquery(squad_ids))
      |> where([m], m.source != "dismissed")
      |> Repo.update_all(
        set: [source: "dismissed", role: "member", updated_at: DateTime.utc_now()]
      )

    count
  end

  # Reports (ADR-143) --------------------------------------------------------

  @impl true
  def create_report(_context, attrs) do
    attrs
    |> Report.changeset()
    |> Repo.insert()
    |> case do
      {:ok, report} -> {:ok, normalize_report(report)}
      error -> error
    end
  end

  @impl true
  def list_reports(_context, filter) do
    Report
    |> then(fn query ->
      case Map.get(filter, :status) do
        nil -> query
        status -> where(query, [r], r.status == ^status)
      end
    end)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^Map.get(filter, :limit, 500))
    |> Repo.all()
    |> Enum.map(&normalize_report/1)
  end

  @impl true
  def resolve_reports(_context, target_type, target_id, attrs) do
    now = DateTime.utc_now()

    {count, _rows} =
      Report
      |> where(
        [r],
        r.target_type == ^target_type and r.target_id == ^target_id and r.status == "open"
      )
      |> Repo.update_all(
        set: [
          status: attrs.status,
          resolution: attrs.resolution,
          resolved_by_id: attrs.resolved_by_id,
          resolved_at: now,
          updated_at: now
        ]
      )

    count
  end

  @impl true
  def reported_ids(_context, reporter_id, target_type) do
    Report
    |> where([r], r.reporter_id == ^reporter_id and r.target_type == ^target_type)
    |> select([r], r.target_id)
    |> Repo.all()
  end

  @impl true
  def hide_comment(_context, id, attrs) do
    PostComment
    |> where([c], c.id == ^id and is_nil(c.deleted_at))
    |> Repo.update_all(
      set: [
        hidden_at: attrs.hidden_at,
        hidden_by_id: attrs.hidden_by_id,
        updated_at: DateTime.utc_now()
      ]
    )
    |> case do
      {1, _} -> :ok
      _none -> {:error, :not_found}
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
        touch_channel(post)
        {:ok, get_post(context, post.id, post.author_id)}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :client_operation_id),
          do: replayed_post(context, attrs, changeset),
          else: {:error, changeset}
    end
  end

  # A post keeps its channel alive: the quiet-group sweep counts from here.
  defp touch_channel(post) do
    Channel
    |> where([ch], ch.id == ^post.channel_id)
    |> Repo.update_all(set: [last_post_at: post.inserted_at, archive_warned_at: nil])
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
    |> media_shown_to(viewer_id)
    |> not_reported_by(viewer_id)
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
    |> media_shown_to(viewer_id)
    |> order_by([p], desc: p.pinned_at)
    |> limit(10)
    |> with_counts(viewer_id)
    |> Repo.all()
  end

  # Posts staff made public, from any of `organization_ids`; readable from
  # any session (ADR-142).
  @impl true
  def list_public_posts(_context, [], _viewer_id, _page), do: []

  def list_public_posts(_context, organization_ids, viewer_id, page) do
    Post
    |> where([p], p.organization_id in ^organization_ids and p.audience == "public")
    |> where([p], is_nil(p.deleted_at) and is_nil(p.hidden_at))
    |> media_shown_to(viewer_id)
    |> only_ids(Map.get(page, :ids))
    |> before(Map.get(page, :before))
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^Map.get(page, :limit, 20))
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

  # ADR-157: a post whose media are not ready (processing, held, failed)
  # shows to its author only.
  defp media_shown_to(query, viewer_id) when is_binary(viewer_id),
    do: where(query, [p], p.media_status == "ready" or p.author_id == ^viewer_id)

  defp media_shown_to(query, _viewer_id), do: where(query, [p], p.media_status == "ready")

  # What someone reported disappears for them (board 7 Q4).
  defp not_reported_by(query, viewer_id) do
    where(
      query,
      [p],
      fragment(
        "NOT EXISTS (SELECT 1 FROM community_reports r WHERE r.target_type = 'post' AND r.target_id = ? AND r.reporter_id = ?)",
        p.id,
        type(^viewer_id, :binary_id)
      )
    )
  end

  defp maybe_author(query, nil), do: query
  defp maybe_author(query, author_id), do: where(query, [p], p.author_id == ^author_id)

  defp only_ids(query, nil), do: query
  defp only_ids(query, ids), do: where(query, [p], p.id in ^ids)

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
      media: p.media,
      media_status: p.media_status,
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

  # ADR-157: read-modify-write of a post's media under a row lock, so two
  # refreshes (two uploads finishing at once) never interleave.
  @impl true
  def update_post_media(_context, id, fun) when is_function(fun, 1) do
    Repo.transaction(fn ->
      Post
      |> where([p], p.id == ^id and is_nil(p.deleted_at))
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> case do
        nil ->
          Repo.rollback(:not_found)

        post ->
          before = post_media_view(post)

          case fun.(before) do
            {:ok, attrs} ->
              case post |> Post.media_changeset(attrs) |> Repo.update() do
                {:ok, updated} -> {before, post_media_view(updated)}
                {:error, changeset} -> Repo.rollback(changeset)
              end

            :skip ->
              {before, before}
          end
      end
    end)
    |> case do
      {:ok, {before, later}} -> {:ok, before, later}
      {:error, reason} -> {:error, reason}
    end
  end

  defp post_media_view(%Post{} = post) do
    %{
      id: post.id,
      organization_id: post.organization_id,
      club_id: post.club_id,
      channel_id: post.channel_id,
      author_id: post.author_id,
      audience: post.audience,
      media: post.media || [],
      media_status: post.media_status
    }
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
    |> Map.take([
      :id,
      :organization_id,
      :kind,
      :name,
      :join_policy,
      :description,
      :cover_media_id,
      :created_by_id,
      :archived_at
    ])
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
      :description,
      :created_by_id,
      :join_policy,
      :status,
      :decided_at,
      :last_post_at,
      :archive_warned_at,
      :archived_at,
      :inserted_at
    ])
  end

  defp normalize_comment(comment),
    do:
      Map.take(comment, [
        :id,
        :organization_id,
        :post_id,
        :author_id,
        :body,
        :hidden_at,
        :inserted_at
      ])

  defp normalize_report(report) do
    Map.take(report, [
      :id,
      :organization_id,
      :club_id,
      :channel_id,
      :target_type,
      :target_id,
      :target_author_id,
      :reporter_id,
      :reason,
      :note,
      :status,
      :resolution,
      :resolved_by_id,
      :resolved_at,
      :inserted_at
    ])
  end

  defp escape_like(text), do: String.replace(text, ~r/[\\%_]/, &"\\#{&1}")
end
