defmodule Palee.Application.ProcessMedia do
  @moduledoc """
  ADR-157: turns a verified post upload (and, since ADR-158, a body photo)
  into what readers get, in the
  background (`ProcessMediaJob`), in its owner's session.

  - Photo: probed (a decompression-bomb guard), decoded, turned upright,
    stripped of every metadata block (EXIF with GPS, XMP, IPTC) and
    re-encoded into `thumb` (320), `feed` (1080) and `full` (2048) WebP
    renditions plus a tiny blurred placeholder.
  - Video: probed (at most two minutes), transcoded to one H.264/AAC MP4 with
    no metadata, and its poster frame processed like a photo.

  The original is deleted once the renditions are stored, so nothing the
  camera wrote stays anywhere. An upload that cannot be processed is
  `rejected` (with its reason); a failure that may pass (storage briefly
  unavailable) is retried, and rejected on the last attempt. Either way the
  post (or body snapshot) it belongs to is refreshed.
  """

  require Logger

  alias Palee.Application.{MediaConsumers, MediaStorage, MediaTools}
  alias Palee.Media
  alias Palee.Workers.ProcessMediaJob

  @bucket :media_private
  @rendition_names ~w(thumb feed full video)

  @doc "Schedules processing (inline when background jobs are disabled, e.g. in tests)."
  def enqueue(%{user_id: user_id}, media_id) do
    if MediaTools.background?() do
      {:ok, _job} =
        %{"user_id" => user_id, "media_id" => media_id}
        |> ProcessMediaJob.new()
        |> Oban.insert()

      :ok
    else
      _result = call(%{user_id: user_id}, media_id, final: true)
      :ok
    end
  end

  @doc "Processes one upload; `final: true` rejects instead of asking for a retry."
  def call(%{user_id: _user_id} = context, media_id, opts \\ []) do
    case Media.get(context, :account, media_id) do
      %{status: "processing"} = media -> run(context, media, opts)
      nil -> {:ok, :gone}
      _done -> {:ok, :skipped}
    end
  end

  defp run(context, media, opts) do
    owner = MediaStorage.owner(context, :account)

    work_dir =
      Path.join(
        System.tmp_dir!(),
        "palee-media-#{media.id}-#{System.unique_integer([:positive])}"
      )

    result =
      try do
        with :ok <- File.mkdir_p(work_dir),
             source = Path.join(work_dir, "source"),
             :ok <- download(owner, media, source) do
          build(Media.kind(media.purpose), owner, media, source, work_dir)
        end
      after
        File.rm_rf(work_dir)
      end

    case result do
      {:ok, attrs} -> finish(context, owner, media, attrs)
      {:error, reason} -> fail(context, owner, media, reason, Keyword.get(opts, :final, false))
    end
  end

  defp download(owner, media, path) do
    case MediaStorage.download(owner, @bucket, media.object_key, path) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :media_upload_missing}
      {:error, _reason} -> {:error, :media_storage_unavailable}
    end
  end

  defp build("image", owner, media, source, work_dir) do
    with {:ok, image} <- image(source, media.content_type, work_dir),
         {:ok, variants} <- store(owner, media, image.renditions) do
      {:ok,
       %{
         width: image.width,
         height: image.height,
         byte_size: Enum.sum(Enum.map(image.renditions, & &1.bytes)),
         content_type: "image/webp",
         variants: variants,
         placeholder: image.placeholder
       }}
    end
  end

  defp build("video", owner, media, source, work_dir) do
    transcoder = MediaTools.video_transcoder()
    poster_dir = Path.join(work_dir, "poster")

    with true <- transcoder.available?() || {:error, :video_unavailable},
         {:ok, probe} <- transcoder.probe(source),
         :ok <- Media.validate_video(probe),
         {:ok, video} <- transcoder.transcode(source, Media.video_spec(), work_dir),
         :ok <- File.mkdir_p(poster_dir),
         {:ok, poster} <- image(video.poster_path, "image/jpeg", poster_dir),
         rendition = %{
           name: "video",
           path: video.path,
           content_type: video.content_type,
           extension: "mp4",
           width: video.width,
           height: video.height,
           bytes: video.bytes
         },
         {:ok, variants} <- store(owner, media, poster.renditions ++ [rendition]) do
      {:ok,
       %{
         width: video.width,
         height: video.height,
         byte_size: video.bytes,
         content_type: video.content_type,
         duration_ms: video.duration_ms,
         variants: variants,
         placeholder: poster.placeholder
       }}
    end
  end

  defp image(source, content_type, work_dir) do
    processor = MediaTools.image_processor()

    with {:ok, probe} <- processor.probe(source, content_type),
         :ok <- Media.validate_image(probe) do
      processor.process(source, content_type, Media.image_spec(), work_dir)
    end
  end

  defp store(owner, media, renditions) do
    Enum.reduce_while(renditions, {:ok, %{}}, fn rendition, {:ok, acc} ->
      key = Media.variant_key(media.object_key, rendition.name, rendition.extension)

      with {:ok, body} <- File.read(rendition.path),
           :ok <- MediaStorage.put(owner, @bucket, key, body, rendition.content_type) do
        {:cont,
         {:ok,
          Map.put(acc, rendition.name, %{
            "key" => key,
            "content_type" => rendition.content_type,
            "width" => rendition.width,
            "height" => rendition.height,
            "bytes" => rendition.bytes
          })}}
      else
        _failed -> {:halt, {:error, :media_storage_unavailable}}
      end
    end)
  end

  defp finish(context, owner, media, attrs) do
    # The original still carries what the camera wrote; only renditions stay.
    _deleted = MediaStorage.delete(owner, [%{bucket: @bucket, key: media.object_key}])

    case Media.mark_processed(context, :account, media.id, attrs) do
      {:ok, ready} ->
        after_change(context, ready)
        {:ok, ready}

      {:error, :media_not_found} ->
        # Deleted (or rejected) meanwhile: drop what was just stored.
        delete_renditions(owner, media)
        {:ok, :gone}
    end
  end

  defp fail(context, owner, media, reason, final?) do
    if Media.rejection?(reason) or final? do
      Logger.info("media_rejected media_id=#{media.id} reason=#{inspect(reason)}")
      delete_renditions(owner, media)
      rejection = if Media.rejection?(reason), do: reason, else: :media_processing_failed

      case Media.mark_rejected(context, :account, media.id, rejection) do
        {:ok, rejected} -> after_change(context, rejected)
        {:error, _gone} -> :ok
      end

      {:ok, :rejected}
    else
      {:error, reason}
    end
  end

  defp delete_renditions(owner, media) do
    keys =
      [media.object_key | Enum.map(@rendition_names, &rendition_key(media, &1))]
      |> Enum.map(&%{bucket: @bucket, key: &1})

    _deleted = MediaStorage.delete(owner, keys)
    :ok
  end

  defp rendition_key(media, "video"), do: Media.variant_key(media.object_key, "video", "mp4")
  defp rendition_key(media, name), do: Media.variant_key(media.object_key, name, "webp")

  # The upload may have been attached while it was processing.
  defp after_change(context, media) do
    current = Media.get(context, :account, media.id) || media
    MediaConsumers.refresh(context, current)
  end
end
