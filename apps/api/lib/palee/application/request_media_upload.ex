defmodule Palee.Application.RequestMediaUpload do
  @moduledoc """
  ADR-148: reserves a media row and issues a presigned PUT for it. The
  browser uploads straight to object storage, then calls
  `CompleteMediaUpload` with the returned `media_id`. Who may upload which
  purpose is decided by the caller's use case (`authorize` below).

  ADR-157: anyone signed in uploads photos and videos for their posts, one
  upload per file, as soon as it is picked. They are the person's own media
  (their account scope), so the compose may still change its destination.
  A quota guard caps open uploads and stored bytes per person, and a video
  is refused up front when this server cannot transcode one.
  """

  alias Palee.Application.{MediaStorage, MediaTools}
  alias Palee.{Media, Organizations}

  @expires_in 900

  def call(context, purpose, params, now \\ DateTime.utc_now()) when is_map(params) do
    with :ok <- authorize(context, purpose), do: reserve(context, purpose, params, now)
  end

  @doc """
  Reserves an upload the caller has already authorized (ADR-158: a body
  photo, once the person's consent is checked by `BodyPhotos`).
  """
  def reserve(context, purpose, params, now \\ DateTime.utc_now()) when is_map(params) do
    content_type = params[:content_type] || params["content_type"]
    byte_size = params[:byte_size] || params["byte_size"]
    id = Ecto.UUID.generate()

    with :ok <- guard(context, purpose, now),
         {:ok, allocation} <- Media.allocate(purpose, content_type, byte_size, id),
         owner = MediaStorage.owner(context, allocation.scope),
         key = MediaStorage.object_key(owner, allocation.relative_key),
         {:ok, upload} <-
           MediaStorage.presigned_upload(owner, allocation.bucket, key, content_type),
         {:ok, media} <-
           Media.create(context, allocation.scope, %{
             id: id,
             purpose: purpose,
             object_key: key,
             content_type: content_type
           }) do
      {:ok,
       %{
         media_id: media.id,
         upload_url: upload.url,
         required_headers: upload.headers,
         expires_in: @expires_in,
         max_bytes: allocation.max_bytes
       }}
    end
  end

  defp guard(context, "post_video", now) do
    if MediaTools.video_available?(),
      do: guard(context, "post_photo", now),
      else: {:error, :video_unavailable}
  end

  defp guard(context, purpose, now) when purpose in ["post_photo", "body_photo", "meal_photo"] do
    since = DateTime.add(now, -Media.orphan_after_seconds())
    context |> Media.usage(:account, since) |> Media.check_quota()
  end

  defp guard(_context, _purpose, _now), do: :ok

  # Box photos speak for the gym: staff who manage its settings.
  defp authorize(context, "box_photo") do
    if Organizations.can?(context, :manage_settings),
      do: :ok,
      else: {:error, :forbidden}
  end

  # ADR-190: product photos, by staff who manage the shop.
  defp authorize(context, "shop_product_photo") do
    if Organizations.can?(context, :manage_shop),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp authorize(%{user_id: user_id}, purpose)
       when purpose in ["post_photo", "post_video"] and is_binary(user_id),
       do: :ok

  defp authorize(_context, purpose) do
    if purpose in Media.purposes(),
      do: {:error, :forbidden},
      else: {:error, :invalid_media_purpose}
  end
end
