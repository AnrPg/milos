defmodule MilosTraining.Application.CompleteMediaUpload do
  @moduledoc """
  ADR-148: verifies an uploaded object and marks its media `ready`. The
  stored bytes decide, not the client: real type and dimensions are read from
  the object's leading bytes, and an image that still carries metadata
  (EXIF, XMP, IPTC) is refused. A refused object is deleted with its row.
  """

  alias MilosTraining.Application.{MediaStorage, MediaUrls}
  alias MilosTraining.Media

  def call(context, purpose, media_id) do
    scope = Media.scope(purpose)

    with %{status: status, purpose: ^purpose} = media <-
           Media.get(context, scope, media_id) || :missing,
         :pending <- if(status == "pending", do: :pending, else: {:ready, media}),
         owner = MediaStorage.owner(context, scope),
         {:ok, inspected, byte_size} <- verify(owner, media) do
      {:ok, ready} =
        Media.mark_ready(context, scope, media.id, %{
          byte_size: byte_size,
          width: inspected.width,
          height: inspected.height
        })

      {:ok, MediaUrls.present(context, ready)}
    else
      {:ready, media} -> {:ok, MediaUrls.present(context, media)}
      {:error, reason} -> {:error, reason}
      _missing -> {:error, :media_not_found}
    end
  end

  defp verify(owner, media) do
    bucket = Media.bucket(media.purpose)

    case MediaStorage.probe(owner, bucket, media.object_key, Media.probe_bytes()) do
      {:ok, %{head: head, byte_size: byte_size}} ->
        with {:ok, inspected} <- Media.inspect_image(head),
             :ok <- Media.validate_stored(media.content_type, inspected, byte_size) do
          {:ok, inspected, byte_size}
        else
          {:error, reason} -> reject(owner, media, reason)
        end

      {:error, :not_found} ->
        {:error, :media_upload_missing}

      {:error, _reason} ->
        {:error, :media_storage_unavailable}
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
