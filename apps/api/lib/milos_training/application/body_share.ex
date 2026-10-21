defmodule MilosTraining.Application.BodyShare do
  @moduledoc """
  Sharing a before/after (ADR-158, board 13 Q6): two of the person's
  snapshots, the photo of one pose from each, as a post with optional text.

  - Optional and explicit: the request must carry `confirm: true`, a second
    confirmation separate from saving the snapshots (plan §6 ethics: photos
    never posted without one). Body photos also need an active consent.
  - Owner only: both snapshots must be the person's own.
  - No numbers are added: the post carries only the text the person typed.
  - The two photos are **copied** into new post uploads (renditions already
    stripped of metadata), so the post never points at body storage, and
    deleting body photos later does not break it.
  - Audiences are those of posts: `followers` or `public` (a profile post),
    or `club_channel` with a `channel_id` (a club post).
  """

  alias MilosTraining.Application.{
    CommunityPosts,
    MediaStorage,
    ProfilePosts,
    ReleaseMedia
  }

  alias MilosTraining.{Body, Media}

  @bucket :media_private

  def call(%{user_id: user_id} = context, params) do
    with :ok <- confirmed(param(params, "confirm")),
         :ok <- context |> Body.list_consents(user_id) |> Body.require_photo_consent(),
         {:ok, pose} <- pose(param(params, "pose")),
         {:ok, before, later} <- snapshots(context, user_id, params),
         {:ok, photos} <- photos(context, [before, later], pose),
         {:ok, copies} <- copy_all(context, user_id, photos) do
      case post(context, params, Enum.map(copies, & &1.id)) do
        {:ok, post} ->
          {:ok, post}

        {:error, reason} ->
          :ok = ReleaseMedia.call(context, :account, Enum.map(copies, & &1.id))
          {:error, reason}
      end
    end
  end

  defp confirmed(true), do: :ok
  defp confirmed(_other), do: {:error, :share_confirmation_required}

  defp pose(pose) when is_binary(pose) do
    if pose in Body.poses(), do: {:ok, pose}, else: {:error, :invalid_pose}
  end

  defp pose(_pose), do: {:error, :invalid_pose}

  defp snapshots(context, user_id, params) do
    from = Body.get_snapshot(context, user_id, param(params, "from_snapshot_id") || "")
    to = Body.get_snapshot(context, user_id, param(params, "to_snapshot_id") || "")

    cond do
      is_nil(from) or is_nil(to) -> {:error, :not_found}
      from.id == to.id -> {:error, :share_needs_two_snapshots}
      DateTime.compare(from.taken_at, to.taken_at) == :gt -> {:ok, to, from}
      true -> {:ok, from, to}
    end
  end

  defp photos(context, snapshots, pose) do
    all = Body.list_photos(context, Enum.map(snapshots, & &1.id))

    snapshots
    |> Enum.map(fn snapshot ->
      Enum.find(
        all,
        &(&1.snapshot_id == snapshot.id and &1.pose == pose and &1.status == "ready")
      )
    end)
    |> case do
      [%{} = first, %{} = second] -> {:ok, [first, second]}
      _missing -> {:error, :share_photo_missing}
    end
  end

  defp copy_all(context, user_id, photos) do
    Enum.reduce_while(photos, {:ok, []}, fn photo, {:ok, acc} ->
      case copy(context, user_id, photo) do
        {:ok, media} ->
          {:cont, {:ok, [media | acc]}}

        {:error, reason} ->
          :ok = ReleaseMedia.call(context, :account, Enum.map(acc, & &1.id))
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, copies} -> {:ok, Enum.reverse(copies)}
      error -> error
    end
  end

  # A new post upload with its own copies of the renditions.
  defp copy(context, user_id, photo) do
    owner = {:account, user_id}
    id = Ecto.UUID.generate()
    key = MediaStorage.object_key(owner, "media/posts/#{id}/original.webp")

    with {:ok, media} <-
           Media.create(context, :account, %{
             id: id,
             purpose: "post_photo",
             object_key: key,
             content_type: "image/webp"
           }),
         {:ok, variants} <- copy_variants(owner, key, photo.variants || %{}),
         bytes = variants |> Map.values() |> Enum.map(&(&1["bytes"] || 0)) |> Enum.sum(),
         {:ok, _processing} <-
           Media.mark_processing(context, :account, media.id, %{
             byte_size: bytes,
             content_type: "image/webp"
           }),
         {:ok, ready} <-
           Media.mark_processed(context, :account, media.id, %{
             width: photo.width,
             height: photo.height,
             byte_size: bytes,
             content_type: "image/webp",
             variants: variants,
             placeholder: photo.placeholder
           }) do
      {:ok, ready}
    else
      {:error, reason} ->
        :ok = ReleaseMedia.call(context, :account, [id])
        {:error, reason}
    end
  end

  defp copy_variants(owner, key, variants) do
    dir =
      Path.join(System.tmp_dir!(), "milos-body-share-#{System.unique_integer([:positive])}")

    try do
      :ok = File.mkdir_p(dir)

      Enum.reduce_while(variants, {:ok, %{}}, fn {name, meta}, {:ok, acc} ->
        target = Media.variant_key(key, name, "webp")
        path = Path.join(dir, name)
        content_type = meta["content_type"] || "image/webp"

        with :ok <- MediaStorage.download(owner, @bucket, meta["key"], path),
             {:ok, body} <- File.read(path),
             :ok <- MediaStorage.put(owner, @bucket, target, body, content_type) do
          {:cont, {:ok, Map.put(acc, name, Map.put(meta, "key", target))}}
        else
          _failed -> {:halt, {:error, :media_storage_unavailable}}
        end
      end)
    after
      File.rm_rf(dir)
    end
  end

  defp post(context, params, media_ids) do
    attrs = %{
      body: param(params, "text"),
      media_ids: media_ids,
      client_operation_id: param(params, "client_operation_id")
    }

    case param(params, "audience") do
      audience when audience in ["followers", "public"] ->
        ProfilePosts.create(context, Map.put(attrs, :audience, audience))

      "club_channel" ->
        CommunityPosts.create(
          context,
          Map.merge(attrs, %{audience: "club_channel", channel_id: param(params, "channel_id")})
        )

      _other ->
        {:error, :invalid_audience}
    end
  end

  defp param(params, key),
    do: Enum.find_value(params, fn {k, value} -> if to_string(k) == key, do: value end)
end
