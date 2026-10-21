defmodule Palee.Application.MyMedia do
  @moduledoc """
  ADR-157: a person's own post uploads, between picking a file and after
  posting: what this server accepts, an upload's state (the compose polls it
  while it processes), its alternative text, an AI suggestion for that text,
  and discarding an upload that is not in a post.

  The suggestion uses the configured `ImageDescriber` on the photo's `feed`
  rendition (a video's poster), in the language asked for, else the
  person's own language, else Greek. It goes back to the person only and is
  never saved; one call is metered like the workout icons (ADR-152).
  """

  alias Palee.Application.{MediaStorage, MediaTools, MediaUrls, PostMedia, ReleaseMedia}
  alias Palee.{Community, Media}

  @max_alt_text 500
  @max_suggestion 300
  @max_image_bytes 8 * 1_024 * 1_024

  @doc "What the compose may offer on this server."
  def capabilities do
    %{
      max_photos: Community.max_post_images(),
      max_videos: 1,
      video: MediaTools.video_available?(),
      max_video_seconds: div(Media.max_video_ms(), 1_000),
      photo_content_types: Media.content_types("post_photo") |> Enum.sort(),
      video_content_types: Media.content_types("post_video") |> Enum.sort(),
      max_photo_bytes: Media.max_bytes("post_photo"),
      max_video_bytes: Media.max_bytes("post_video"),
      max_alt_text: @max_alt_text
    }
  end

  def get(context, id) do
    with {:ok, media} <- own(context, id), do: {:ok, MediaUrls.present(context, media)}
  end

  @doc "Sets (or clears, with blank text) an upload's alternative text; its post follows."
  def update_alt_text(context, id, text) do
    with {:ok, text} <- normalize_alt_text(text),
         {:ok, _media} <- own(context, id),
         {:ok, media} <- Media.update_alt_text(context, :account, id, text) do
      _refreshed = media |> PostMedia.ref_of() |> PostMedia.refresh()
      {:ok, MediaUrls.present(context, media)}
    end
  end

  @doc "Removes an upload the person took out of the compose (only while not in a post)."
  def discard(context, id) do
    with {:ok, media} <- own(context, id),
         true <- is_nil(media.attached_at) || {:error, :media_in_post} do
      ReleaseMedia.call(context, :account, [media.id])
    end
  end

  def suggest_alt_text(context, id, params) do
    with {:ok, media} <- own(context, id),
         {:ok, key} <- describable(media),
         {:ok, bytes} <- read(context, key),
         {:ok, text} <-
           MediaTools.image_describer().describe(
             %{bytes: bytes, content_type: "image/webp"},
             %{locale: locale(context, params)},
             metering(context)
           ),
         {:ok, suggestion} <- clean(text) do
      {:ok, %{suggestion: suggestion}}
    else
      {:error, :not_configured} -> {:error, :alt_text_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp own(%{user_id: user_id} = context, id) when is_binary(user_id) do
    case Media.get(context, :account, id) do
      %{purpose: purpose} = media ->
        if purpose in Media.post_purposes(), do: {:ok, media}, else: {:error, :media_not_found}

      nil ->
        {:error, :media_not_found}
    end
  end

  defp own(_context, _id), do: {:error, :media_not_found}

  defp describable(%{status: "ready", variants: %{"feed" => %{"key" => key}}}), do: {:ok, key}
  defp describable(_media), do: {:error, :media_not_ready}

  defp read(context, key) do
    case MediaStorage.probe(
           MediaStorage.owner(context, :account),
           :media_private,
           key,
           @max_image_bytes
         ) do
      {:ok, %{head: bytes}} when byte_size(bytes) > 0 -> {:ok, bytes}
      {:ok, _empty} -> {:error, :media_not_ready}
      {:error, _reason} -> {:error, :media_storage_unavailable}
    end
  end

  defp locale(context, params) do
    requested = params[:locale] || params["locale"]
    account = Map.get(context, :account)

    cond do
      is_binary(requested) and requested != "" ->
        requested

      is_map(account) and is_binary(Map.get(account, :preferred_locale)) ->
        account.preferred_locale

      true ->
        "el"
    end
  end

  defp clean(text) when is_binary(text) do
    suggestion =
      text
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.trim("\"")
      |> String.trim("«")
      |> String.trim("»")
      |> String.slice(0, @max_suggestion)

    if suggestion == "", do: {:error, :alt_text_unavailable}, else: {:ok, suggestion}
  end

  defp clean(_text), do: {:error, :alt_text_unavailable}

  defp normalize_alt_text(nil), do: {:ok, nil}

  defp normalize_alt_text(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:ok, nil}
      trimmed when byte_size(trimmed) > 0 -> length_ok(trimmed)
    end
  end

  defp normalize_alt_text(_text), do: {:error, :invalid_alt_text}

  defp length_ok(text) do
    if String.length(text) <= @max_alt_text, do: {:ok, text}, else: {:error, :invalid_alt_text}
  end

  # ADR-152: metered for the gym the request is made in, when there is one.
  defp metering(context) do
    %{
      organization_id: Map.get(context, :organization_id),
      user_id: Map.get(context, :user_id),
      operation_id: Ecto.UUID.generate(),
      feature: "post_alt_text"
    }
  end
end
