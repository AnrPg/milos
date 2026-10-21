defmodule Palee.Application.CompleteMediaUpload do
  @moduledoc """
  ADR-148: verifies an uploaded object and marks its media `ready`. The
  stored bytes decide, not the client: real type and dimensions are read from
  the object's leading bytes, and an image that still carries metadata
  (EXIF, XMP, IPTC) is refused. A refused object is deleted with its row.

  ADR-157: a post photo or video is checked the same way for type and size
  (it may still carry metadata), then moves to `processing` and is handed to
  `ProcessMedia`, which strips it and builds its renditions in the
  background. The answer shows the media as it is then.
  """

  alias Palee.Application.{MediaStorage, MediaUrls, ProcessMedia}
  alias Palee.Media

  def call(context, purpose, media_id) do
    scope = Media.scope(purpose)

    with %{status: status, purpose: ^purpose} = media <-
           Media.get(context, scope, media_id) || :missing,
         :pending <- if(status == "pending", do: :pending, else: {:done, media}),
         owner = MediaStorage.owner(context, scope),
         {:ok, media} <- complete(Media.processing(purpose), context, owner, media) do
      {:ok, MediaUrls.present(context, media)}
    else
      {:done, media} -> {:ok, MediaUrls.present(context, media)}
      {:error, reason} -> {:error, reason}
      _missing -> {:error, :media_not_found}
    end
  end

  defp complete(:inspect, context, owner, media) do
    with {:ok, inspected, byte_size} <- verify(owner, media) do
      Media.mark_ready(context, media.scope, media.id, %{
        byte_size: byte_size,
        width: inspected.width,
        height: inspected.height
      })
    end
  end

  defp complete(:server, context, owner, media) do
    with {:ok, content_type, byte_size} <- verify_upload(owner, media),
         {:ok, processing} <-
           Media.mark_processing(context, media.scope, media.id, %{
             byte_size: byte_size,
             content_type: content_type
           }) do
      :ok = ProcessMedia.enqueue(context, processing.id)
      {:ok, Media.get(context, media.scope, media.id) || processing}
    end
  end

  defp verify(owner, media) do
    with {:ok, %{head: head, byte_size: byte_size}} <- probe(owner, media) do
      with {:ok, inspected} <- Media.inspect_image(head),
           :ok <- Media.validate_stored(media.content_type, inspected, byte_size) do
        {:ok, inspected, byte_size}
      else
        {:error, reason} -> reject(owner, media, reason)
      end
    end
  end

  defp verify_upload(owner, media) do
    with {:ok, %{head: head, byte_size: byte_size}} <- probe(owner, media) do
      with {:ok, sniffed} <- Media.sniff(head),
           {:ok, content_type} <- Media.validate_upload(media.purpose, sniffed, byte_size) do
        {:ok, content_type, byte_size}
      else
        {:error, reason} -> reject(owner, media, reason)
      end
    end
  end

  defp probe(owner, media) do
    case MediaStorage.probe(
           owner,
           Media.bucket(media.purpose),
           media.object_key,
           Media.probe_bytes()
         ) do
      {:ok, %{head: _head, byte_size: _size} = probe} -> {:ok, probe}
      {:error, :not_found} -> {:error, :media_upload_missing}
      {:error, _reason} -> {:error, :media_storage_unavailable}
    end
  end

  defp reject(owner, media, reason) do
    bucket = Media.bucket(media.purpose)
    MediaStorage.delete(owner, [%{bucket: bucket, key: media.object_key}])
    Media.delete(owner_context(owner), Media.scope(media.purpose), [media.id])
    {:error, reason}
  end

  defp owner_context({:tenant, organization_id}), do: %{organization_id: organization_id}
  defp owner_context({:account, user_id}), do: %{user_id: user_id}
end
