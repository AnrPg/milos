defmodule MilosTraining.Infrastructure.Community.EctoSocialStore do
  @moduledoc "Ecto adapter of follows and profile posts (ADR-142)."

  @behaviour MilosTraining.Community.Ports.SocialStore

  import Ecto.Query

  alias MilosTraining.Community.{
    Follow,
    ProfilePost,
    ProfilePostComment,
    ProfilePostReaction
  }

  alias MilosTraining.Repo

  @follow_fields [:id, :user_id, :target_type, :target_id, :status, :accepted_at, :inserted_at]

  # Follows -------------------------------------------------------------------

  @impl true
  def get_follow(_context, follower_id, type, target_id) do
    Follow
    |> where([f], f.user_id == ^follower_id and f.target_type == ^type)
    |> where([f], f.target_id == ^target_id)
    |> Repo.one()
    |> normalize_follow()
  end

  @impl true
  def get_follow_by_id(_context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Follow |> Repo.get(id) |> normalize_follow()
      :error -> nil
    end
  end

  @impl true
  def insert_follow(_context, attrs) do
    attrs
    |> Follow.changeset()
    |> Repo.insert()
    |> case do
      {:ok, follow} -> {:ok, normalize_follow(follow)}
      error -> error
    end
  end

  @impl true
  def delete_follow(_context, follower_id, type, target_id) do
    Follow
    |> where([f], f.user_id == ^follower_id and f.target_type == ^type)
    |> where([f], f.target_id == ^target_id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def accept_follow(_context, id, now) do
    Follow
    |> where([f], f.id == ^id and f.status == "requested")
    |> select([f], f)
    |> Repo.update_all(set: [status: "active", accepted_at: now, updated_at: now])
    |> case do
      {1, [follow]} -> {:ok, normalize_follow(follow)}
      _none -> {:error, :not_found}
    end
  end

  @impl true
  def delete_follow_by_id(_context, id) do
    case Follow |> where([f], f.id == ^id) |> Repo.delete_all() do
      {1, _} -> :ok
      _none -> {:error, :not_found}
    end
  end

  @impl true
  def list_incoming(_context, type, target_id, status, page) do
    Follow
    |> where([f], f.target_type == ^type and f.target_id == ^target_id and f.status == ^status)
    |> page(page)
    |> Repo.all()
    |> Enum.map(&normalize_follow/1)
  end

  @impl true
  def list_outgoing(_context, follower_id, types, statuses, page) do
    Follow
    |> where([f], f.user_id == ^follower_id and f.target_type in ^types and f.status in ^statuses)
    |> page(page)
    |> Repo.all()
    |> Enum.map(&normalize_follow/1)
  end

  @impl true
  def count_incoming(_context, type, target_id, status) do
    Follow
    |> where([f], f.target_type == ^type and f.target_id == ^target_id and f.status == ^status)
    |> Repo.aggregate(:count)
  end

  @impl true
  def count_outgoing(_context, follower_id, types, statuses) do
    Follow
    |> where([f], f.user_id == ^follower_id and f.target_type in ^types and f.status in ^statuses)
    |> Repo.aggregate(:count)
  end

  @impl true
  def active_target_ids(_context, follower_id, type) do
    Follow
    |> where([f], f.user_id == ^follower_id and f.target_type == ^type and f.status == "active")
    |> select([f], f.target_id)
    |> Repo.all()
  end

  @impl true
  def follow_statuses(_context, _follower_id, _type, []), do: %{}

  def follow_statuses(_context, follower_id, type, ids) do
    Follow
    |> where([f], f.user_id == ^follower_id and f.target_type == ^type and f.target_id in ^ids)
    |> select([f], {f.target_id, f.status})
    |> Repo.all()
    |> Map.new()
  end

  # Visible to anyone: numbers only, through a SECURITY DEFINER function.
  @impl true
  def follower_counts(_type, []), do: %{}

  def follower_counts(type, ids) do
    %{rows: rows} =
      Repo.query!("SELECT target_id, followers FROM milos_follow_counts($1, $2)", [
        type,
        Enum.map(ids, &Ecto.UUID.dump!/1)
      ])

    counts = Map.new(rows, fn [id, count] -> {Ecto.UUID.load!(id), count} end)
    Map.new(ids, &{&1, Map.get(counts, &1, 0)})
  end

  @impl true
  def following_count(user_id) do
    %{rows: [[count]]} =
      Repo.query!("SELECT milos_following_count($1)", [Ecto.UUID.dump!(user_id)])

    count
  end

  # Profile posts -------------------------------------------------------------

  @impl true
  def create_profile_post(context, attrs) do
    attrs
    |> ProfilePost.changeset()
    |> Repo.insert()
    |> case do
      {:ok, post} -> {:ok, get_profile_post(context, post.id, post.user_id)}
      error -> error
    end
  end

  @impl true
  def get_profile_post(_context, id, viewer_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        ProfilePost
        |> where([p], p.id == ^id and is_nil(p.deleted_at))
        |> with_counts(viewer_id)
        |> Repo.one()

      :error ->
        nil
    end
  end

  @impl true
  def list_profile_posts(_context, %{author_ids: []}), do: []

  def list_profile_posts(_context, filter) do
    ProfilePost
    |> where([p], p.user_id in ^filter.author_ids and is_nil(p.deleted_at))
    |> before(Map.get(filter, :before))
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^filter.limit)
    |> with_counts(filter.viewer_id)
    |> Repo.all()
  end

  @impl true
  def count_profile_posts(_context, author_id) do
    ProfilePost
    |> where([p], p.user_id == ^author_id and is_nil(p.deleted_at))
    |> Repo.aggregate(:count)
  end

  @impl true
  def delete_profile_post(_context, id, now) do
    ProfilePost
    |> where([p], p.id == ^id and is_nil(p.deleted_at))
    |> Repo.update_all(set: [deleted_at: now, updated_at: now])
    |> case do
      {1, _} -> :ok
      _none -> {:error, :not_found}
    end
  end

  @impl true
  def react_profile_post(_context, post_id, user_id, kind) do
    Repo.insert_all(
      ProfilePostReaction,
      [
        %{
          id: Ecto.UUID.generate(),
          post_id: post_id,
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
  def unreact_profile_post(_context, post_id, user_id, kind) do
    ProfilePostReaction
    |> where([r], r.post_id == ^post_id and r.user_id == ^user_id and r.kind == ^kind)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def list_profile_comments(_context, post_id) do
    ProfilePostComment
    |> where([c], c.post_id == ^post_id and is_nil(c.deleted_at))
    |> order_by([c], asc: c.inserted_at, asc: c.id)
    |> Repo.all()
    |> Enum.map(&normalize_comment/1)
  end

  @impl true
  def get_profile_comment(_context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %ProfilePostComment{deleted_at: nil} = comment <- Repo.get(ProfilePostComment, id) do
      normalize_comment(comment)
    else
      _missing -> nil
    end
  end

  @impl true
  def add_profile_comment(_context, attrs) do
    attrs
    |> ProfilePostComment.changeset()
    |> Repo.insert()
    |> case do
      {:ok, comment} -> {:ok, normalize_comment(comment)}
      error -> error
    end
  end

  @impl true
  def delete_profile_comment(_context, id, now) do
    ProfilePostComment
    |> where([c], c.id == ^id and is_nil(c.deleted_at))
    |> Repo.update_all(set: [deleted_at: now, updated_at: now])
    |> case do
      {1, _} -> :ok
      _none -> {:error, :not_found}
    end
  end

  # Helpers -------------------------------------------------------------------

  defp page(query, page) do
    query
    |> before(Map.get(page, :before))
    |> order_by([f], desc: f.inserted_at, desc: f.id)
    |> limit(^Map.get(page, :limit, 50))
  end

  defp before(query, nil), do: query

  defp before(query, {%DateTime{} = at, id}),
    do: where(query, [r], r.inserted_at < ^at or (r.inserted_at == ^at and r.id < ^id))

  defp with_counts(query, viewer_id) do
    select(query, [p], %{
      id: p.id,
      author_id: p.user_id,
      audience: p.audience,
      body: p.body,
      attachment_type: p.attachment_type,
      attachment_id: p.attachment_id,
      attachment: p.attachment,
      inserted_at: p.inserted_at,
      kudos_count:
        fragment(
          "(SELECT count(*) FROM community_profile_post_reactions r WHERE r.post_id = ? AND r.kind = 'kudos')",
          p.id
        ),
      comment_count:
        fragment(
          "(SELECT count(*) FROM community_profile_post_comments c WHERE c.post_id = ? AND c.deleted_at IS NULL)",
          p.id
        ),
      kudos_by_me:
        fragment(
          "EXISTS (SELECT 1 FROM community_profile_post_reactions r WHERE r.post_id = ? AND r.kind = 'kudos' AND r.user_id = ?)",
          p.id,
          type(^viewer_id, :binary_id)
        )
    })
  end

  defp normalize_follow(nil), do: nil
  defp normalize_follow(follow), do: Map.take(follow, @follow_fields)

  defp normalize_comment(comment) do
    %{
      id: comment.id,
      post_id: comment.post_id,
      author_id: comment.user_id,
      body: comment.body,
      inserted_at: comment.inserted_at
    }
  end
end
