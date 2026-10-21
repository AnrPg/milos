defmodule Palee.Application.BodyPhotos do
  @moduledoc """
  Body photos (ADR-158): front, side, back (and other) pictures of a
  snapshot, through the ADR-157 upload pipeline (presigned PUT, server-side
  stripping and renditions) but in the person's private storage only.

  - A photo needs an active `body_photos` consent, asked once before the
    first upload (plan D8).
  - An upload is attached to its snapshot (`body_snapshot`); the snapshot's
    photo row copies the renditions' keys when processing finishes, so a
    coach session can be given signed URLs without reading media rows.
  - Removing a photo deletes the upload and every rendition; "delete all
    photos" deletes every body upload, any leftover object under the
    person's body folder, and snapshots that are left with nothing.
  """

  alias Palee.Application.{
    BodyPresenter,
    CompleteMediaUpload,
    MediaStorage,
    ReleaseMedia,
    RequestMediaUpload
  }

  alias Palee.{Body, Media}

  @purpose "body_photo"

  @doc "What the photo step may offer on this server."
  def capabilities do
    %{
      content_types: Media.content_types(@purpose) |> Enum.sort(),
      max_bytes: Media.max_bytes(@purpose),
      max_photos: Body.max_photos(),
      poses: Body.poses()
    }
  end

  @doc "Reserves an upload for a body photo (needs the consent)."
  def request_upload(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with :ok <- consented(context, user_id) do
      RequestMediaUpload.reserve(context, @purpose, params, now)
    end
  end

  @doc """
  Validates `entries` (`[%{"media_id", "pose"}]`) for a snapshot that already
  has `existing_poses`: the consent, the poses, and each upload being the
  person's own unattached body photo. Returns `[{media, pose}]`.
  """
  def prepare(_context, [], _existing_poses), do: {:ok, []}

  def prepare(%{user_id: user_id} = context, entries, existing_poses) when is_list(entries) do
    with :ok <- consented(context, user_id),
         {:ok, pairs} <- parse(entries),
         :ok <- Body.validate_photos(existing_poses, Enum.map(pairs, &elem(&1, 1))),
         true <- Enum.uniq_by(pairs, &elem(&1, 0)) == pairs || {:error, :invalid_media} do
      found =
        context |> Media.list(:account, Enum.map(pairs, &elem(&1, 0))) |> Map.new(&{&1.id, &1})

      Enum.reduce_while(pairs, {:ok, []}, fn {id, pose}, {:ok, acc} ->
        case Map.get(found, id) do
          %{purpose: @purpose, attached_at: nil, status: status} = media
          when status != "rejected" ->
            {:cont, {:ok, [{media, pose} | acc]}}

          _other ->
            {:halt, {:error, :invalid_media}}
        end
      end)
      |> case do
        {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
        error -> error
      end
    end
  end

  def prepare(_context, _entries, _existing_poses), do: {:error, :invalid_media}

  defp parse(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      id = entry_field(entry, "media_id")
      pose = entry_field(entry, "pose")

      case Ecto.UUID.cast(id) do
        {:ok, id} when is_binary(pose) -> {:cont, {:ok, [{id, pose} | acc]}}
        _invalid -> {:halt, {:error, :invalid_media}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      error -> error
    end
  end

  defp entry_field(entry, key) when is_map(entry),
    do: Map.get(entry, key) || Map.get(entry, String.to_existing_atom(key))

  defp entry_field(_entry, _key), do: nil

  @doc """
  Attaches prepared uploads to a snapshot: finishes an upload not completed
  yet (processing starts), attaches it and records the photo row.
  """
  def attach(context, snapshot, prepared, now \\ DateTime.utc_now()) do
    Enum.reduce_while(prepared, {:ok, []}, fn {media, pose}, {:ok, acc} ->
      case attach_one(context, snapshot, media, pose, now) do
        {:ok, photo} -> {:cont, {:ok, [photo | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, photos} -> {:ok, Enum.reverse(photos)}
      error -> error
    end
  end

  defp attach_one(%{user_id: user_id} = context, snapshot, media, pose, now) do
    attachment = %{type: "body_snapshot", id: snapshot.id}

    with :ok <- complete(context, media),
         {:ok, 1} <- Media.attach(context, :account, [media.id], attachment, now),
         {:ok, photo} <-
           Body.insert_photo(context, %{
             user_id: user_id,
             snapshot_id: snapshot.id,
             media_id: media.id,
             pose: pose,
             status: "processing"
           }) do
      # Processing may have finished before the row existed.
      current = Media.get(context, :account, media.id)
      if current, do: refresh(context, current)
      {:ok, Body.get_photo(context, user_id, photo.id) || photo}
    else
      {:ok, 0} -> {:error, :invalid_media}
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete(context, %{status: "pending", id: id}) do
    case CompleteMediaUpload.call(context, @purpose, id) do
      {:ok, _media} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete(_context, _media), do: :ok

  @doc "Adds one photo to a snapshot (`%{media_id, pose}`)."
  def add(%{user_id: user_id} = context, snapshot_id, params, now \\ DateTime.utc_now()) do
    with %{} = snapshot <-
           Body.get_snapshot(context, user_id, snapshot_id) || {:error, :not_found},
         existing = Body.list_photos(context, [snapshot.id]),
         {:ok, prepared} <- prepare(context, [params], Enum.map(existing, & &1.pose)),
         {:ok, [photo]} <- attach(context, snapshot, prepared, now) do
      {:ok, BodyPresenter.photo(photo, user_id)}
    end
  end

  @doc "Removes a photo; a snapshot keeps at least one metric or photo."
  def remove(%{user_id: user_id} = context, snapshot_id, photo_id) do
    with %{} = snapshot <-
           Body.get_snapshot(context, user_id, snapshot_id) || {:error, :not_found},
         photos = Body.list_photos(context, [snapshot.id]),
         %{} = photo <- Enum.find(photos, &(&1.id == photo_id)) || {:error, :not_found},
         :ok <- Body.validate_content(Body.clean_metrics(snapshot.metrics), length(photos) - 1),
         {:ok, _deleted} <- Body.delete_photo(context, user_id, photo.id) do
      ReleaseMedia.call(context, :account, [photo.media_id])
    end
  end

  @doc "Releases the uploads of photos being deleted with their snapshot."
  def release(_context, []), do: :ok

  def release(context, photos),
    do: ReleaseMedia.call(context, :account, Enum.map(photos, & &1.media_id))

  @doc "The latest ready photo of each pose, for the camera's ghost outline."
  def latest(%{user_id: user_id} = context) do
    context
    |> Body.latest_photos(user_id)
    |> Enum.map(&BodyPresenter.photo(&1, user_id))
  end

  @doc """
  Deletes every body photo of the person: uploads with their renditions,
  any object left under their body folder, and snapshots left empty.
  """
  def delete_all(%{user_id: user_id} = context) do
    ids = Media.list_ids_by_purpose(context, :account, @purpose)
    :ok = ReleaseMedia.call(context, :account, ids)
    purge_leftovers(user_id)
    snapshots = Body.delete_empty_snapshots(context, user_id)
    {:ok, %{deleted_photos: length(ids), deleted_snapshots: snapshots}}
  end

  defp purge_leftovers(user_id) do
    owner = {:account, user_id}
    folder = MediaStorage.object_key(owner, "media/body/")

    case MediaStorage.list_account(user_id) do
      {:ok, objects} ->
        leftovers =
          for %{key: key, bucket: bucket} <- objects,
              String.starts_with?(key, folder),
              do: %{bucket: bucket, key: key}

        _deleted = MediaStorage.delete(owner, leftovers)
        :ok

      _error ->
        :ok
    end
  end

  @doc "A body upload changed (processed, rejected): its photo row follows."
  def refresh(_context, %{owner_id: owner_id} = media) do
    attrs =
      case media.status do
        "ready" ->
          %{
            status: "ready",
            variants: media.variants || %{},
            width: media.width,
            height: media.height,
            placeholder: media.placeholder
          }

        status ->
          %{status: Body.photo_status(status)}
      end

    Body.refresh_photo(%{user_id: owner_id}, media.id, attrs)
  end

  defp consented(context, user_id),
    do: context |> Body.list_consents(user_id) |> Body.require_photo_consent()
end
