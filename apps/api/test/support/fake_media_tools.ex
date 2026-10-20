defmodule MilosTraining.FakeImageProcessor do
  @moduledoc """
  Test stand-in for ImageMagick (ADR-157). Reads JPEG dimensions from the
  frame header, refuses files containing `UNREADABLE`, and writes renditions
  of a few bytes of "WebP".
  """

  @behaviour MilosTraining.Application.Ports.ImageProcessor

  @impl true
  def available?, do: true

  @impl true
  def probe(path, _content_type) do
    with {:ok, body} <- File.read(path) do
      cond do
        String.contains?(body, "UNREADABLE") -> {:error, :media_unreadable}
        String.contains?(body, "HUGE") -> {:ok, %{width: 10_000, height: 10_000}}
        true -> {:ok, dimensions(body)}
      end
    end
  end

  @impl true
  def process(path, _content_type, spec, work_dir) do
    {:ok, body} = File.read(path)
    %{width: width, height: height} = dimensions(body)

    renditions =
      Enum.map(spec.variants, fn variant ->
        scale = min(1.0, variant.max_edge / max(width, height))
        out = Path.join(work_dir, "#{variant.name}.webp")
        File.write!(out, "RIFF-fake-webp-#{variant.name}")

        %{
          name: variant.name,
          path: out,
          content_type: "image/webp",
          extension: "webp",
          width: round(width * scale),
          height: round(height * scale),
          bytes: File.stat!(out).size
        }
      end)

    full = Enum.max_by(renditions, & &1.width)

    {:ok,
     %{
       width: full.width,
       height: full.height,
       renditions: renditions,
       placeholder: "data:image/webp;base64,ZmFrZQ=="
     }}
  end

  # Start-of-frame markers carry the dimensions; anything else is 1600×1200.
  defp dimensions(<<0xFF, 0xD8, rest::binary>>), do: sof(rest)
  defp dimensions(_body), do: %{width: 1600, height: 1200}

  defp sof(<<0xFF, marker, _len::16, _p, height::16, width::16, _::binary>>)
       when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC],
       do: %{width: width, height: height}

  defp sof(<<0xFF, marker, length::16, rest::binary>>) when marker not in [0xD8, 0xD9, 0xDA] do
    case rest do
      <<_segment::binary-size(length - 2), next::binary>> -> sof(next)
      _short -> %{width: 1600, height: 1200}
    end
  end

  defp sof(_other), do: %{width: 1600, height: 1200}
end

defmodule MilosTraining.FakeVideoTranscoder do
  @moduledoc """
  Test stand-in for ffmpeg (ADR-157): a 12-second 1920×1080 video, or 90
  seconds when the upload contains `LONG`. `available?/0` follows
  `:fake_video_available` (default true).
  """

  @behaviour MilosTraining.Application.Ports.VideoTranscoder

  @impl true
  def available?, do: Application.get_env(:milos_training, :fake_video_available, true)

  @impl true
  def probe(path) do
    {:ok, body} = File.read(path)
    duration = if String.contains?(body, "LONG"), do: 90_000, else: 12_000
    {:ok, %{duration_ms: duration, width: 1920, height: 1080, has_video: true}}
  end

  @impl true
  def transcode(_path, spec, work_dir) do
    out = Path.join(work_dir, "video.mp4")
    poster = Path.join(work_dir, "poster.jpg")
    File.write!(out, "fake-mp4")
    File.write!(poster, MilosTraining.TestSupport.ImageFixtures.jpeg(1920, 1080))

    {:ok,
     %{
       path: out,
       content_type: "video/mp4",
       width: spec.max_edge,
       height: div(spec.max_edge * 9, 16),
       duration_ms: 12_000,
       bytes: 8,
       poster_path: poster
     }}
  end
end

defmodule MilosTraining.FakeImageDescriber do
  @moduledoc "Test stand-in for the alt text model (ADR-157); tells the test process it was asked."

  @behaviour MilosTraining.Application.Ports.ImageDescriber

  @impl true
  def describe(%{bytes: _bytes}, %{locale: locale}, metering) do
    send(self(), {:described, locale, metering})

    case {Application.get_env(:milos_training, :fake_describer_configured, true), locale} do
      {false, _locale} -> {:error, :not_configured}
      {true, "el"} -> {:ok, "  «Αθλήτρια σηκώνει μπάρα σε box» \n"}
      {true, _other} -> {:ok, "An athlete lifts a barbell in a gym"}
    end
  end
end
