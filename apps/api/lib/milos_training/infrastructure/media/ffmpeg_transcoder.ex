defmodule MilosTraining.Infrastructure.Media.FfmpegTranscoder do
  @moduledoc """
  `VideoTranscoder` on ffmpeg/ffprobe (ADR-157). One H.264 (yuv420p,
  `veryfast`, CRF 26) + AAC (128 kb/s stereo) MP4 with `+faststart`, at most
  `max_edge` on its long side and never upscaled; ffmpeg turns the picture
  upright itself, and `-map_metadata -1 -map_chapters -1` drops every
  metadata block (GPS location, device, dates). The poster is a JPEG frame
  from the first second of the result. Runs are killed after five minutes.
  """

  @behaviour MilosTraining.Application.Ports.VideoTranscoder

  alias MilosTraining.Infrastructure.Media.CommandRunner

  @timeout_ms 300_000

  @impl true
  def available?, do: not is_nil(tools())

  @impl true
  def probe(path) do
    with {:ok, {_ffmpeg, ffprobe}} <- fetch_tools(),
         {:ok, output} <-
           run(ffprobe, [
             "-v",
             "error",
             "-print_format",
             "json",
             "-show_format",
             "-show_streams",
             path
           ]),
         {:ok, json} <- Jason.decode(output) do
      {:ok, parse_probe(json)}
    else
      {:error, :media_processing_unavailable} -> {:error, :video_unavailable}
      _unreadable -> {:error, :media_unreadable}
    end
  end

  @impl true
  def transcode(path, spec, work_dir) do
    out = Path.join(work_dir, "video.mp4")
    poster = Path.join(work_dir, "poster.jpg")
    edge = Integer.to_string(spec.max_edge)
    seconds = :erlang.float_to_binary(spec.max_duration_ms / 1_000, decimals: 3)

    scale =
      "scale='min(#{edge},iw)':'min(#{edge},ih)':force_original_aspect_ratio=decrease:" <>
        "force_divisible_by=2,format=yuv420p"

    with {:ok, {ffmpeg, _ffprobe}} <- fetch_tools(),
         {:ok, _output} <-
           run(ffmpeg, [
             "-nostdin",
             "-y",
             "-v",
             "error",
             "-i",
             path,
             "-map",
             "0:v:0",
             "-map",
             "0:a:0?",
             "-map_metadata",
             "-1",
             "-map_chapters",
             "-1",
             "-sn",
             "-dn",
             "-t",
             seconds,
             "-vf",
             scale,
             "-c:v",
             "libx264",
             "-preset",
             "veryfast",
             "-crf",
             "26",
             "-c:a",
             "aac",
             "-b:a",
             "128k",
             "-ac",
             "2",
             "-movflags",
             "+faststart",
             out
           ]),
         {:ok, result} <- probe(out),
         {:ok, _output} <-
           run(ffmpeg, [
             "-nostdin",
             "-y",
             "-v",
             "error",
             "-ss",
             poster_at(result.duration_ms),
             "-i",
             out,
             "-frames:v",
             "1",
             "-q:v",
             "3",
             poster
           ]),
         {:ok, %{size: bytes}} <- File.stat(out) do
      {:ok,
       %{
         path: out,
         content_type: "video/mp4",
         width: result.width,
         height: result.height,
         duration_ms: result.duration_ms,
         bytes: bytes,
         poster_path: poster
       }}
    else
      {:error, :media_processing_unavailable} -> {:error, :video_unavailable}
      {:error, :timeout} -> {:error, :media_processing_failed}
      {:error, {:exit, _status, _output}} -> {:error, :media_unreadable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp poster_at(duration_ms),
    do: :erlang.float_to_binary(min(1.0, duration_ms / 2_000), decimals: 3)

  @doc false
  def parse_probe(json) do
    streams = Map.get(json, "streams", [])
    video = Enum.find(streams, &(&1["codec_type"] == "video"))
    duration = parse_seconds(get_in(json, ["format", "duration"]) || (video && video["duration"]))

    {width, height} =
      case video do
        nil -> {0, 0}
        stream -> upright(stream["width"] || 0, stream["height"] || 0, rotation(stream))
      end

    %{
      has_video: not is_nil(video),
      duration_ms: round(duration * 1_000),
      width: width,
      height: height
    }
  end

  defp upright(width, height, rotation) when rotation in [90, 270, -90, -270],
    do: {height, width}

  defp upright(width, height, _rotation), do: {width, height}

  defp rotation(stream) do
    side_data =
      stream
      |> Map.get("side_data_list", [])
      |> Enum.find_value(fn data -> data["rotation"] end)

    tag = get_in(stream, ["tags", "rotate"])

    cond do
      is_number(side_data) -> round(side_data)
      is_binary(tag) -> String.to_integer(tag)
      true -> 0
    end
  rescue
    _invalid -> 0
  end

  defp parse_seconds(value) when is_binary(value) do
    case Float.parse(value) do
      {seconds, _rest} -> seconds
      :error -> 0.0
    end
  end

  defp parse_seconds(value) when is_number(value), do: value * 1.0
  defp parse_seconds(_value), do: 0.0

  defp run(executable, args), do: CommandRunner.run(executable, args, @timeout_ms)

  defp fetch_tools do
    case tools() do
      nil -> {:error, :media_processing_unavailable}
      tools -> {:ok, tools}
    end
  end

  defp tools do
    with ffmpeg when is_binary(ffmpeg) <- System.find_executable("ffmpeg"),
         ffprobe when is_binary(ffprobe) <- System.find_executable("ffprobe") do
      {ffmpeg, ffprobe}
    end
  end
end
