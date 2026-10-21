defmodule Palee.Infrastructure.Media.ImageMagickProcessor do
  @moduledoc """
  `ImageProcessor` on the ImageMagick command line (ADR-157): `magick` on
  ImageMagick 7 (the Alpine API image), `convert`/`identify` on 6.

  - The input coder is named from the type the upload's bytes showed
    (`jpeg:`, `png:`, `webp:`, `heic:`), so a crafted file cannot switch
    ImageMagick to another decoder (SVG, MVG, …).
  - Resource limits bound memory, disk, pixels and time per run, and the
    runner kills a run that outlives its wall-clock limit.
  - One decode: the image is turned upright (`-auto-orient`), stripped of
    every profile and comment (`-strip`, which drops EXIF and GPS), resized
    to the largest rendition, and the smaller ones are cloned from it. All
    renditions are WebP; the placeholder is a 16 px WebP data URI.
  """

  @behaviour Palee.Application.Ports.ImageProcessor

  alias Palee.Infrastructure.Media.CommandRunner

  @timeout_ms 120_000
  @coders %{
    "image/jpeg" => "jpeg",
    "image/png" => "png",
    "image/webp" => "webp",
    "image/heic" => "heic",
    "image/heif" => "heic"
  }
  @limits [
    ["-limit", "memory", "256MiB"],
    ["-limit", "map", "512MiB"],
    ["-limit", "disk", "1GiB"],
    ["-limit", "area", "128MP"],
    ["-limit", "time", "110"]
  ]

  @impl true
  def available?, do: not is_nil(tools())

  @impl true
  def probe(path, content_type) do
    with {:ok, coder} <- coder(content_type),
         {:ok, {_convert, identify}} <- fetch_tools(),
         {:ok, output} <-
           identify(identify, ["-ping", "-format", "%w %h %[orientation]\\n", input(coder, path)]) do
      parse_probe(output)
    end
  end

  @impl true
  def process(path, content_type, spec, work_dir) do
    with {:ok, coder} <- coder(content_type),
         {:ok, {convert, identify}} <- fetch_tools() do
      [largest | smaller] = Enum.sort_by(spec.variants, & &1.max_edge, :desc)
      placeholder_path = Path.join(work_dir, "placeholder.webp")

      clones =
        Enum.map(smaller, &clone(&1.max_edge, &1.quality, out(work_dir, &1.name))) ++
          [clone(spec.placeholder_edge, 40, placeholder_path)]

      args =
        List.flatten([
          @limits,
          input(coder, path),
          ["-auto-orient", "-strip", "-resize", "#{largest.max_edge}x#{largest.max_edge}>"],
          clones,
          ["-quality", Integer.to_string(largest.quality), "webp:" <> out(work_dir, largest.name)]
        ])

      with {:ok, _output} <- run(convert, args),
           {:ok, renditions} <- renditions(identify, spec.variants, work_dir),
           {:ok, placeholder} <- File.read(placeholder_path) do
        full = Enum.max_by(renditions, & &1.width)

        {:ok,
         %{
           width: full.width,
           height: full.height,
           renditions: renditions,
           placeholder: "data:image/webp;base64," <> Base.encode64(placeholder)
         }}
      else
        {:error, :timeout} -> {:error, :media_processing_failed}
        {:error, {:exit, _status, _output}} -> {:error, :media_unreadable}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp clone(edge, quality, path) do
    [
      "(",
      "+clone",
      "-resize",
      "#{edge}x#{edge}>",
      "-quality",
      Integer.to_string(quality),
      "-write",
      "webp:" <> path,
      "+delete",
      ")"
    ]
  end

  defp out(work_dir, name), do: Path.join(work_dir, "#{name}.webp")

  defp renditions(identify, variants, work_dir) do
    Enum.reduce_while(variants, {:ok, []}, fn variant, {:ok, acc} ->
      path = out(work_dir, variant.name)

      with {:ok, output} <- identify(identify, ["-ping", "-format", "%w %h", "webp:" <> path]),
           [width, height] <- output |> String.split() |> Enum.map(&String.to_integer/1),
           {:ok, %{size: bytes}} <- File.stat(path) do
        rendition = %{
          name: variant.name,
          path: path,
          content_type: "image/webp",
          extension: "webp",
          width: width,
          height: height,
          bytes: bytes
        }

        {:cont, {:ok, acc ++ [rendition]}}
      else
        _failed -> {:halt, {:error, :media_processing_failed}}
      end
    end)
  end

  # Orientations 5–8 swap the stored width and height once turned upright.
  @rotated ~w(LeftTop RightTop RightBottom LeftBottom)

  defp parse_probe(output) do
    case output |> String.split("\n", trim: true) |> List.first("") |> String.split(" ") do
      [width, height | orientation] ->
        with {w, ""} <- Integer.parse(width), {h, ""} <- Integer.parse(height) do
          if Enum.join(orientation) in @rotated,
            do: {:ok, %{width: h, height: w}},
            else: {:ok, %{width: w, height: h}}
        else
          _invalid -> {:error, :media_unreadable}
        end

      _invalid ->
        {:error, :media_unreadable}
    end
  end

  defp identify({executable, prefix}, args) do
    case CommandRunner.run(executable, prefix ++ List.flatten(@limits) ++ args, @timeout_ms) do
      {:ok, output} -> {:ok, output}
      {:error, _reason} -> {:error, :media_unreadable}
    end
  end

  defp run({executable, prefix}, args),
    do: CommandRunner.run(executable, prefix ++ args, @timeout_ms)

  defp input(coder, path), do: "#{coder}:#{path}[0]"

  defp coder(content_type) do
    case Map.fetch(@coders, content_type) do
      {:ok, coder} -> {:ok, coder}
      :error -> {:error, :invalid_media_type}
    end
  end

  defp fetch_tools do
    case tools() do
      nil -> {:error, :media_processing_unavailable}
      tools -> {:ok, tools}
    end
  end

  defp tools do
    case System.find_executable("magick") do
      nil ->
        with convert when is_binary(convert) <- System.find_executable("convert"),
             identify when is_binary(identify) <- System.find_executable("identify") do
          {{convert, []}, {identify, []}}
        end

      magick ->
        {{magick, []}, {magick, ["identify"]}}
    end
  end
end
