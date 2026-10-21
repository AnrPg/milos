defmodule Palee.Application.PostMedia do
  @moduledoc """
  Photos and videos attached to posts (ADR-157). The author's uploads (Media,
  their account scope) are the source of truth; the post keeps an ordered
  snapshot of what readers need (renditions, sizes, placeholder, alt text)
  and a status, so a feed never reads media rows across people.

  `refresh/1` recomputes a post's snapshot and status from its uploads under
  a row lock. It runs whenever something changed: the post was created, an
  upload finished processing or was rejected, the author edited alt text.
  It is idempotent.
  """

  alias Palee.Application.{RealtimePublisher, ReleaseMedia}
  alias Palee.{Community, Media}

  @doc """
  Validates the media ids of a new post by the context's user: their own
  uploads, not yet in a post, not rejected, at most ten photos or one
  video. Returns the uploads in the given order.
  """
  def prepare(_context, nil), do: {:ok, []}
  def prepare(_context, []), do: {:ok, []}

  def prepare(%{user_id: user_id}, ids) when is_list(ids) and is_binary(user_id) do
    with true <- Enum.all?(ids, &is_binary/1) || {:error, :invalid_media},
         true <- Enum.uniq(ids) == ids || {:error, :invalid_media},
         true <- length(ids) <= Community.max_post_images() || {:error, :too_many_media},
         found = %{user_id: user_id} |> Media.list(:account, ids) |> Map.new(&{&1.id, &1}),
         {:ok, media} <- ordered(ids, found),
         :ok <- Community.validate_post_media(Enum.map(media, &Media.kind(&1.purpose))) do
      {:ok, media}
    end
  end

  def prepare(_context, _ids), do: {:error, :invalid_media}

  defp ordered(ids, found) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case Map.get(found, id) do
        %{purpose: purpose, status: status, attached_at: nil} = media
        when status != "rejected" ->
          if purpose in Media.post_purposes(),
            do: {:cont, {:ok, [media | acc]}},
            else: {:halt, {:error, :invalid_media}}

        _other ->
          {:halt, {:error, :invalid_media}}
      end
    end)
    |> case do
      {:ok, media} -> {:ok, Enum.reverse(media)}
      error -> error
    end
  end

  @doc "The media fields a new post starts with."
  def initial(media) do
    entries = Enum.map(media, &entry/1)
    %{media: entries, media_status: Community.post_media_status(states(entries))}
  end

  @doc """
  Attaches the uploads to the post they were prepared for, then refreshes
  it. Replaying the same post (an outbox retry) finds them attached already.
  """
  def attach([], _context, _ref), do: :ok

  def attach(media, %{user_id: user_id}, ref) do
    ids = Enum.map(media, & &1.id)
    attachment = %{type: ref.type, id: ref.id, organization_id: Map.get(ref, :organization_id)}
    {:ok, attached} = Media.attach(%{user_id: user_id}, :account, ids, attachment, now())

    already =
      %{user_id: user_id}
      |> Media.list(:account, ids)
      |> Enum.count(&(&1.attached_type == ref.type and &1.attached_id == ref.id))

    if attached == length(ids) or already == length(ids) do
      _result = refresh(ref)
      :ok
    else
      {:error, :invalid_media}
    end
  end

  @post_types ~w(community_post profile_post)

  @doc "The post an upload belongs to, as `refresh/1` takes it, or nil (not in a post)."
  def ref_of(%{attached_type: type, attached_id: id} = media) when type in @post_types do
    %{
      type: type,
      id: id,
      organization_id: Map.get(media, :attached_organization_id),
      author_id: media.owner_id
    }
  end

  def ref_of(_media), do: nil

  @doc "The post's own reference: `community_post` (with its gym) or `profile_post`."
  def ref("community_post", post),
    do: %{
      type: "community_post",
      id: post.id,
      organization_id: post.organization_id,
      author_id: post.author_id
    }

  def ref("profile_post", post),
    do: %{type: "profile_post", id: post.id, organization_id: nil, author_id: post.author_id}

  @doc "Recomputes the post's snapshot and status; acts on what changed."
  def refresh(nil), do: {:ok, :none}

  def refresh(ref) do
    case Community.update_post_media(post_context(ref), ref.type, ref.id, &recompute/1) do
      {:ok, before, later} ->
        changed(ref, before, later)
        {:ok, later}

      {:error, :not_found} ->
        {:ok, :gone}

      error ->
        error
    end
  end

  defp recompute(post) do
    ids = Enum.map(post.media, &entry_id/1)
    found = %{user_id: post.author_id} |> Media.list(:account, ids) |> Map.new(&{&1.id, &1})

    entries =
      Enum.map(post.media, fn old ->
        case Map.get(found, entry_id(old)) do
          nil -> Map.put(old, "status", "missing")
          media -> entry(media)
        end
      end)

    {:ok,
     %{
       media: entries,
       media_status: Community.post_media_status(states(entries))
     }}
  end

  defp changed(ref, before, later) do
    if before.media_status != later.media_status or before.media != later.media,
      do: announce(ref, later)

    :ok
  end

  @doc """
  The snapshot a post keeps of one upload: string keys (it is stored as
  JSON), renditions by name with their keys, no original key.
  """
  def entry(media) do
    %{
      "id" => media.id,
      "kind" => Media.kind(media.purpose),
      "status" => media.status,
      "width" => media.width,
      "height" => media.height,
      "alt_text" => media.alt_text,
      "placeholder" => media.placeholder,
      "duration_ms" => media.duration_ms,
      "variants" => media.variants || %{}
    }
  end

  @doc "Ids of a post's media, in order."
  def ids(%{media: entries}) when is_list(entries), do: Enum.map(entries, &entry_id/1)
  def ids(_post), do: []

  @doc "Deletes a deleted post's uploads (rows and objects), in its author's scope."
  def release(%{author_id: author_id} = post) when is_binary(author_id) do
    case ids(post) do
      [] -> :ok
      ids -> ReleaseMedia.call(%{user_id: author_id}, :account, ids)
    end
  end

  def release(_post), do: :ok

  defp entry_id(entry), do: Map.get(entry, "id") || Map.get(entry, :id)

  defp states(entries), do: Enum.map(entries, &(Map.get(&1, "status") || Map.get(&1, :status)))

  # A club post is written in the scope of the gym that runs its club, a
  # profile post in its author's session.
  def post_context(%{type: "community_post", organization_id: organization_id} = ref),
    do: %{organization_id: organization_id, user_id: ref.author_id}

  def post_context(%{type: "profile_post"} = ref), do: %{user_id: ref.author_id}

  defp announce(%{type: "community_post"} = ref, post) do
    RealtimePublisher.broadcast("community:club:#{post.club_id}", "post_updated", %{
      post_id: ref.id,
      channel_id: post.channel_id
    })
  end

  defp announce(%{type: "profile_post"} = ref, _post) do
    RealtimePublisher.broadcast("community:profile:#{ref.author_id}", "post_updated", %{
      post_id: ref.id
    })
  end

  defp now, do: DateTime.utc_now()
end
