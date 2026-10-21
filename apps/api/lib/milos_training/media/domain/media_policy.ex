defmodule MilosTraining.Media.Domain.MediaPolicy do
  @moduledoc """
  What each kind of upload is (ADR-148, ADR-157): who owns it (a gym or a
  person), which bucket it lives in, where its key goes, which types and
  sizes it accepts and how it becomes `ready`.

  - `:inspect` purposes (box photos) are re-encoded in the browser,
    which drops EXIF and GPS; only JPEG and simple WebP are accepted and
    `ImageInspector` checks the stored bytes before an object becomes `ready`.
  - `:server` purposes (post photos and videos, body photos since ADR-158)
    accept what a phone produces.
    The server decodes them, strips every metadata block, re-encodes them
    into fixed renditions and deletes the original: pending → processing →
    ready | rejected.
  """

  @client_image_types %{"image/jpeg" => "jpg", "image/webp" => "webp"}
  @post_image_types %{
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/webp" => "webp",
    "image/heic" => "heic",
    "image/heif" => "heif"
  }
  @video_types %{"video/mp4" => "mp4", "video/quicktime" => "mov", "video/webm" => "webm"}

  @mb 1_024 * 1_024

  @purposes %{
    "box_photo" => %{
      scope: :tenant,
      bucket: :media_public,
      folder: "media/public/box",
      kind: "image",
      processing: :inspect,
      types: @client_image_types,
      max_bytes: 8 * @mb
    },
    # ADR-158: body photos go through the post pipeline (server-stripped
    # renditions) but never into a post; private bucket, signed URLs only.
    "body_photo" => %{
      scope: :account,
      bucket: :media_private,
      folder: "media/body",
      kind: "image",
      processing: :server,
      post: false,
      types: @post_image_types,
      max_bytes: 25 * @mb
    },
    # ADR-159: an optional photo of a meal; the body-photo pipeline and
    # storage rules (private bucket, never a post, signed URLs only).
    "meal_photo" => %{
      scope: :account,
      bucket: :media_private,
      folder: "media/meals",
      kind: "image",
      processing: :server,
      post: false,
      types: @post_image_types,
      max_bytes: 25 * @mb
    },
    "post_photo" => %{
      scope: :account,
      bucket: :media_private,
      folder: "media/posts",
      kind: "image",
      processing: :server,
      post: true,
      types: @post_image_types,
      max_bytes: 25 * @mb
    },
    "post_video" => %{
      scope: :account,
      bucket: :media_private,
      folder: "media/posts",
      kind: "video",
      processing: :server,
      post: true,
      types: @video_types,
      max_bytes: 500 * @mb
    }
  }

  @statuses ~w(pending processing ready rejected)

  # Client re-encoded images.
  @max_bytes 8 * @mb
  @max_dimension 4_096
  @probe_bytes 128 * 1_024

  # Server-processed images: a decoding guard (pixels) and the renditions.
  @max_pixels 50_000_000
  @image_variants [
    %{name: "thumb", max_edge: 320, quality: 70},
    %{name: "feed", max_edge: 1_080, quality: 80},
    %{name: "full", max_edge: 2_048, quality: 82}
  ]
  @placeholder_edge 16

  # Videos: one H.264/AAC MP4 rendition, at most 720p, at most two minutes.
  @max_video_ms 120_000
  @video_tolerance_ms 500
  @video_max_edge 1_280
  @max_video_pixels 4_096 * 4_096

  # Quota per person: open uploads (not yet in a post) and stored bytes.
  @max_open_uploads 30
  @max_account_bytes 5 * 1_024 * @mb

  # Unattached uploads older than this are swept; so are attached uploads
  # stuck before `ready` (an upload that never finished, a lost job).
  @orphan_after_seconds 24 * 3_600

  @rejections ~w(media_unreadable media_too_large invalid_media_type video_too_long
                 media_upload_missing media_processing_failed video_unavailable
                 media_processing_timeout)a

  def purposes, do: Map.keys(@purposes) |> Enum.sort()
  def tenant_purposes, do: for({p, %{scope: :tenant}} <- @purposes, do: p) |> Enum.sort()
  def account_purposes, do: for({p, %{scope: :account}} <- @purposes, do: p) |> Enum.sort()
  def post_purposes, do: for({p, %{post: true}} <- @purposes, do: p) |> Enum.sort()
  def statuses, do: @statuses
  def rejections, do: @rejections

  @doc "Types a browser-re-encoded image may have (box photos)."
  def content_types, do: Map.keys(@client_image_types) |> Enum.sort()

  @doc "Types an upload of `purpose` may declare."
  def content_types(purpose), do: purpose |> fetch!() |> Map.fetch!(:types) |> Map.keys()

  @doc "Every type a post upload may declare."
  def post_content_types,
    do: Map.keys(@post_image_types) ++ Map.keys(@video_types)

  def max_bytes, do: @max_bytes
  def max_bytes(purpose), do: purpose |> fetch!() |> Map.fetch!(:max_bytes)
  def max_dimension, do: @max_dimension
  def max_pixels, do: @max_pixels
  def probe_bytes, do: @probe_bytes
  def orphan_after_seconds, do: @orphan_after_seconds
  def image_variants, do: @image_variants
  def placeholder_edge, do: @placeholder_edge
  def max_video_ms, do: @max_video_ms
  def video_max_edge, do: @video_max_edge
  def max_open_uploads, do: @max_open_uploads
  def max_account_bytes, do: @max_account_bytes

  @doc "The scope (`:tenant` | `:account`) of a purpose."
  def scope(purpose), do: purpose |> fetch!() |> Map.fetch!(:scope)

  @doc "Logical bucket of a purpose (`:media_public` | `:media_private`)."
  def bucket(purpose), do: purpose |> fetch!() |> Map.fetch!(:bucket)

  @doc "`image` or `video`."
  def kind(purpose), do: purpose |> fetch!() |> Map.fetch!(:kind)

  @doc "`:inspect` (browser re-encoded) or `:server` (processed here)."
  def processing(purpose), do: purpose |> fetch!() |> Map.fetch!(:processing)

  def public?(purpose), do: bucket(purpose) == :media_public

  @doc """
  Validates an upload request and returns the object key relative to its
  owner's prefix (`organizations/<id>/` or `users/<id>/`, added by storage).
  A processed upload gets its own folder: the original and its renditions.
  """
  def allocate(purpose, content_type, byte_size, id) when is_binary(id) do
    with {:ok, spec} <- fetch(purpose),
         {:ok, extension} <- extension(spec, content_type),
         :ok <- validate_size(byte_size, spec.max_bytes) do
      {:ok,
       %{
         scope: spec.scope,
         bucket: spec.bucket,
         relative_key: relative_key(spec, id, extension),
         content_type: content_type,
         max_bytes: spec.max_bytes
       }}
    end
  end

  defp relative_key(%{processing: :server, folder: folder}, id, extension),
    do: "#{folder}/#{id}/original.#{extension}"

  defp relative_key(%{folder: folder}, id, extension), do: "#{folder}/#{id}.#{extension}"

  @doc "Key of a rendition next to a processed upload's original."
  def variant_key(object_key, name, extension) when is_binary(object_key),
    do: Path.dirname(object_key) <> "/#{name}.#{extension}"

  @doc "Validates what was stored against what was requested (browser re-encoded images)."
  def validate_stored(expected_content_type, %{content_type: actual} = inspected, byte_size) do
    cond do
      actual != expected_content_type ->
        {:error, :media_type_mismatch}

      not is_integer(byte_size) or byte_size <= 0 ->
        {:error, :media_upload_missing}

      byte_size > @max_bytes ->
        {:error, :media_too_large}

      inspected.width > @max_dimension or inspected.height > @max_dimension ->
        {:error, :media_too_large}

      true ->
        :ok
    end
  end

  @doc """
  Validates a processed upload's stored bytes: the type its leading bytes
  show must be one the purpose accepts (whatever the browser declared), and
  its size within the purpose's cap. Returns the real type.
  """
  def validate_upload(purpose, sniffed_type, byte_size) do
    spec = fetch!(purpose)

    cond do
      not is_integer(byte_size) or byte_size <= 0 -> {:error, :media_upload_missing}
      not Map.has_key?(spec.types, sniffed_type) -> {:error, :invalid_media_type}
      byte_size > spec.max_bytes -> {:error, :media_too_large}
      true -> {:ok, sniffed_type}
    end
  end

  @doc "Whether a decoded image may be processed (a decompression-bomb guard)."
  def validate_image(%{width: width, height: height})
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    if width * height > @max_pixels, do: {:error, :media_too_large}, else: :ok
  end

  def validate_image(_probe), do: {:error, :media_unreadable}

  @doc "Whether a probed video may be transcoded: it has a picture and lasts at most two minutes."
  def validate_video(%{has_video: false}), do: {:error, :media_unreadable}

  def validate_video(%{duration_ms: duration, width: width, height: height})
      when is_integer(duration) and is_integer(width) and is_integer(height) and width > 0 and
             height > 0 do
    cond do
      duration <= 0 -> {:error, :media_unreadable}
      duration > @max_video_ms + @video_tolerance_ms -> {:error, :video_too_long}
      width * height > @max_video_pixels -> {:error, :media_too_large}
      true -> :ok
    end
  end

  def validate_video(_probe), do: {:error, :media_unreadable}

  @doc "What processing a stored upload needs, for the processor adapters."
  def image_spec, do: %{variants: @image_variants, placeholder_edge: @placeholder_edge}

  def video_spec, do: %{max_edge: @video_max_edge, max_duration_ms: @max_video_ms}

  @doc "Whether a person may start another upload."
  def check_quota(%{open_uploads: open, bytes: bytes}) do
    cond do
      open >= @max_open_uploads -> {:error, :media_quota_exceeded}
      bytes >= @max_account_bytes -> {:error, :media_quota_exceeded}
      true -> :ok
    end
  end

  @doc "Whether a processing error rejects the upload (others are retried)."
  def rejection?(reason), do: reason in @rejections

  @doc "Whether an unattached upload created at `inserted_at` is an orphan at `now`."
  def orphan?(%{attached_at: nil, inserted_at: inserted_at}, %DateTime{} = now),
    do: DateTime.diff(now, inserted_at) >= @orphan_after_seconds

  def orphan?(_media, _now), do: false

  defp fetch(purpose) do
    case Map.fetch(@purposes, purpose) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, :invalid_media_purpose}
    end
  end

  defp fetch!(purpose) do
    {:ok, spec} = fetch(purpose)
    spec
  end

  defp extension(spec, content_type) do
    case Map.fetch(spec.types, content_type) do
      {:ok, extension} -> {:ok, extension}
      :error -> {:error, :invalid_media_type}
    end
  end

  defp validate_size(size, max) when is_integer(size) and size > 0 and size <= max, do: :ok

  defp validate_size(size, _max) when is_integer(size) and size > 0,
    do: {:error, :media_too_large}

  defp validate_size(_size, _max), do: {:error, :invalid_media_size}
end
