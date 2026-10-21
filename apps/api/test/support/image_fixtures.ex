defmodule Palee.TestSupport.ImageFixtures do
  @moduledoc "Leading bytes of small images for media upload tests (ADR-148)."

  import Bitwise

  @doc "A JPEG head with JFIF APP0, an optional extra segment, then SOF0."
  def jpeg(width, height, extra_segments \\ []) do
    app0 = <<0xFF, 0xE0, 16::16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>>
    sof0 = <<0xFF, 0xC0, 17::16, 8, height::16, width::16, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1>>

    IO.iodata_to_binary([
      <<0xFF, 0xD8>>,
      app0,
      extra_segments,
      sof0,
      <<0xFF, 0xDA>>,
      :binary.copy(<<0>>, 64)
    ])
  end

  def exif_segment do
    payload = "Exif" <> <<0, 0>> <> :binary.copy(<<1>>, 20)
    <<0xFF, 0xE1, byte_size(payload) + 2::16, payload::binary>>
  end

  def webp_lossy(width, height) do
    vp8 =
      <<0, 0, 0, 0x9D, 0x01, 0x2A, width::little-16, height::little-16>> <>
        :binary.copy(<<0>>, 32)

    riff("VP8 ", vp8)
  end

  def webp_lossless(width, height) do
    bits = width - 1 ||| (height - 1) <<< 14
    riff("VP8L", <<0x2F, bits::little-32>> <> :binary.copy(<<0>>, 32))
  end

  def webp_extended, do: riff("VP8X", :binary.copy(<<0>>, 10))

  defp riff(chunk, body) do
    payload = chunk <> <<byte_size(body)::little-32>> <> body
    "RIFF" <> <<byte_size(payload) + 4::little-32>> <> "WEBP" <> payload
  end
end
