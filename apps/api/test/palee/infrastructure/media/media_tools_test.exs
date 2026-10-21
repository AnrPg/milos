defmodule Palee.Infrastructure.Media.MediaToolsTest do
  @moduledoc """
  ADR-157: the real ImageMagick and ffmpeg adapters on tiny generated files.
  A JPEG carrying GPS coordinates and a rotation comes out upright with no
  metadata at all; a video carrying a location comes out as an MP4 without
  it. Skipped where the tools are not installed (see test_helper.exs).
  """

  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Media.{FfmpegTranscoder, ImageMagickProcessor}
  alias Palee.Media.Domain.MediaPolicy

  setup do
    dir = Path.join(System.tmp_dir!(), "palee-media-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  @tag :imagemagick
  test "a photo with GPS and a rotation comes out upright and without metadata", %{dir: dir} do
    source = Path.join(dir, "source")
    File.write!(source, jpeg_with_gps(dir, 640, 480))

    # The fixture really carries what a phone writes.
    assert identify(["-format", "%[EXIF:GPSLatitude]", "jpeg:" <> source]) =~ "37/1"

    # Orientation 6: stored landscape, shown portrait.
    assert {:ok, %{width: 480, height: 640}} = ImageMagickProcessor.probe(source, "image/jpeg")

    out = Path.join(dir, "out")
    File.mkdir_p!(out)

    assert {:ok, %{width: 480, height: 640, renditions: renditions, placeholder: placeholder}} =
             ImageMagickProcessor.process(source, "image/jpeg", MediaPolicy.image_spec(), out)

    assert "data:image/webp;base64," <> encoded = placeholder
    assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = Base.decode64!(encoded)

    assert %{"thumb" => thumb, "feed" => feed, "full" => full} =
             Map.new(renditions, &{&1.name, &1})

    assert {thumb.width, thumb.height} == {240, 320}
    assert {feed.width, feed.height} == {480, 640}
    assert {full.width, full.height} == {480, 640}

    for rendition <- renditions do
      bytes = File.read!(rendition.path)
      assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = bytes
      refute bytes =~ "Exif"
      refute bytes =~ "GPS"
      assert identify(["-format", "%[EXIF:*]", "webp:" <> rendition.path]) == ""
    end
  end

  @tag :imagemagick
  test "a file that is not the image it claims is refused", %{dir: dir} do
    source = Path.join(dir, "source")
    File.write!(source, "<svg xmlns='http://www.w3.org/2000/svg'/>")
    assert {:error, :media_unreadable} = ImageMagickProcessor.probe(source, "image/jpeg")
  end

  @tag :ffmpeg
  test "a video with a location becomes an MP4 without it, with a poster", %{dir: dir} do
    source = Path.join(dir, "source.mov")

    {_, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "error",
        "-f",
        "lavfi",
        "-i",
        "testsrc=duration=1:size=320x240:rate=10",
        "-f",
        "lavfi",
        "-i",
        "sine=duration=1",
        "-metadata",
        "location=+37.9838+023.7275/",
        "-metadata",
        "make=TestPhone",
        "-c:v",
        "libx264",
        "-c:a",
        "aac",
        "-shortest",
        source
      ])

    assert probe_tags(source) =~ "37.9838"

    assert {:ok, %{duration_ms: ms, width: 320, height: 240, has_video: true}} =
             FfmpegTranscoder.probe(source)

    assert ms in 900..1_200

    assert {:ok, video} = FfmpegTranscoder.transcode(source, MediaPolicy.video_spec(), dir)
    assert video.content_type == "video/mp4"
    assert {video.width, video.height} == {320, 240}
    assert video.duration_ms in 900..1_200
    refute probe_tags(video.path) =~ "37.9838"
    refute probe_tags(video.path) =~ "TestPhone"
    assert <<0xFF, 0xD8, 0xFF, _::binary>> = File.read!(video.poster_path)
  end

  defp identify(args) do
    {output, 0} =
      case System.find_executable("magick") do
        nil -> System.cmd("identify", args)
        magick -> System.cmd(magick, ["identify" | args])
      end

    String.trim(output)
  end

  defp probe_tags(path) do
    {output, 0} = System.cmd("ffprobe", ["-v", "error", "-show_entries", "format_tags", path])
    output
  end

  # A real JPEG from ImageMagick, with an EXIF block (orientation 6 and GPS
  # latitude 37°58'30" N) inserted right after its start marker.
  defp jpeg_with_gps(dir, width, height) do
    base = Path.join(dir, "base.jpg")
    convert = System.find_executable("magick") || System.find_executable("convert")

    {_, 0} =
      System.cmd(convert, ["-size", "#{width}x#{height}", "gradient:red-blue", "jpeg:" <> base])

    <<0xFF, 0xD8, rest::binary>> = File.read!(base)

    ifd0 =
      <<2::16>> <>
        <<0x0112::16, 3::16, 1::32, 6::16, 0::16>> <>
        <<0x8825::16, 4::16, 1::32, 38::32>> <> <<0::32>>

    gps =
      <<2::16>> <>
        <<0x0001::16, 2::16, 2::32, "N", 0, 0, 0>> <>
        <<0x0002::16, 5::16, 3::32, 68::32>> <> <<0::32>>

    rationals = <<37::32, 1::32, 58::32, 1::32, 3000::32, 100::32>>
    tiff = "MM" <> <<0x2A::16, 8::32>> <> ifd0 <> gps <> rationals
    payload = "Exif" <> <<0, 0>> <> tiff
    <<0xFF, 0xD8, 0xFF, 0xE1, byte_size(payload) + 2::16>> <> payload <> rest
  end
end
