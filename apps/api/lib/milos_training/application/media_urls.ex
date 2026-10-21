defmodule MilosTraining.Application.MediaUrls do
  @moduledoc """
  ADR-148: how a media item is shown to a client: its id, size and a URL
  (stable for public media, presigned and short-lived for private media).
  Callers authorize the reader first; this only builds the URL.

  ADR-157: a processed photo or video also shows its renditions
  (`thumb_url`, `feed_url`, `full_url`; for a video these are its poster),
  the MP4 (`video_url`), its placeholder, alternative text and length.
  URLs are signed for the media's owner (its uploader), whoever reads them.
  """

  alias MilosTraining.Application.MediaStorage
  alias MilosTraining.Media

  @renditions ~w(thumb feed full)

  def present(context, media) do
    owner = owner(context, media)
    bucket = Media.bucket(media.purpose)
    variants = Map.get(media, :variants) || %{}

    url =
      case variants do
        %{"full" => %{"key" => key}} ->
          url(owner, bucket, key)

        _none ->
          if Media.processing(media.purpose) == :inspect, do: url(owner, bucket, media.object_key)
      end

    %{
      id: media.id,
      purpose: media.purpose,
      kind: Media.kind(media.purpose),
      status: media.status,
      content_type: media.content_type,
      width: media.width,
      height: media.height,
      url: url,
      alt_text: Map.get(media, :alt_text),
      placeholder: Map.get(media, :placeholder),
      duration_ms: Map.get(media, :duration_ms),
      rejection_reason: Map.get(media, :rejection_reason)
    }
    |> Map.merge(rendition_urls(owner, bucket, variants))
  end

  def present_all(context, media), do: Enum.map(media, &present(context, &1))

  @doc """
  A post's media as its readers see them, from the snapshot the post keeps
  (`PostMedia.snapshot/1`). `author_id` owns the objects.
  """
  def present_post_media(_author_id, []), do: []

  def present_post_media(author_id, entries) when is_list(entries) do
    owner = {:account, author_id}

    Enum.map(entries, fn entry ->
      variants = if entry["status"] == "ready", do: entry["variants"] || %{}, else: %{}

      %{
        id: entry["id"],
        kind: entry["kind"],
        status: entry["status"],
        width: entry["width"],
        height: entry["height"],
        alt_text: entry["alt_text"],
        placeholder: entry["placeholder"],
        duration_ms: entry["duration_ms"]
      }
      |> Map.merge(rendition_urls(owner, :media_private, variants))
    end)
  end

  def present_post_media(_author_id, _entries), do: []

  defp rendition_urls(owner, bucket, variants) do
    images =
      Map.new(@renditions, fn name ->
        {String.to_atom(name <> "_url"), variant_url(owner, bucket, variants, name)}
      end)

    Map.put(images, :video_url, variant_url(owner, bucket, variants, "video"))
  end

  defp variant_url(owner, bucket, variants, name) do
    case Map.get(variants, name) do
      %{"key" => key} -> url(owner, bucket, key)
      _missing -> nil
    end
  end

  defp url(owner, bucket, key) do
    case MediaStorage.read_url(owner, bucket, key) do
      {:ok, url} -> url
      {:error, _reason} -> nil
    end
  end

  # Account media are signed for their owner, so a follower reading a post
  # gets URLs under its author's prefix; tenant media for their gym.
  defp owner(_context, %{scope: :account, owner_id: user_id}) when is_binary(user_id),
    do: {:account, user_id}

  defp owner(_context, %{scope: :tenant, owner_id: organization_id})
       when is_binary(organization_id),
       do: {:tenant, organization_id}

  defp owner(context, media), do: MediaStorage.owner(context, media.scope)
end
