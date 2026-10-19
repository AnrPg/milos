defmodule MilosTraining.Media.Domain.ImageInspector do
  @moduledoc """
  Reads the leading bytes of an uploaded image (ADR-148): its real type and
  dimensions, and whether it still carries metadata.

  - JPEG: every segment before the first frame header must lie inside the
    probe; APP1 (EXIF, XMP) and APP13 (IPTC) segments are refused.
  - WebP: only the simple formats (`VP8 `, `VP8L`) are accepted. Metadata
    chunks (`EXIF`, `XMP `) exist only in the extended `VP8X` format, which a
    browser canvas never writes, so the simple format cannot carry them.
  """

  import Bitwise

  @doc "`{:ok, %{content_type, width, height}}` or `{:error, reason}`."
  def inspect_image(<<0xFF, 0xD8, rest::binary>>), do: jpeg_segments(rest)

  def inspect_image(<<"RIFF", _size::little-32, "WEBP", chunk::binary-size(4), rest::binary>>),
    do: webp(chunk, rest)

  def inspect_image(_head), do: {:error, :invalid_media_type}

  # --- JPEG ---------------------------------------------------------------

  # Start-of-frame markers carry the dimensions (C0–CF except C4, C8, CC).
  defp jpeg_segments(<<0xFF, marker, rest::binary>>)
       when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC] do
    case rest do
      <<_length::16, _precision, height::16, width::16, _rest::binary>> ->
        dimensions("image/jpeg", width, height)

      _truncated ->
        {:error, :media_unreadable}
    end
  end

  defp jpeg_segments(<<0xFF, marker, _rest::binary>>) when marker in [0xE1, 0xED],
    do: {:error, :media_has_metadata}

  # Fill bytes before a marker.
  defp jpeg_segments(<<0xFF, 0xFF, rest::binary>>), do: jpeg_segments(<<0xFF, rest::binary>>)

  defp jpeg_segments(<<0xFF, marker, length::16, rest::binary>>)
       when marker not in [0xD8, 0xD9, 0xDA] and length >= 2 do
    body = length - 2

    case rest do
      <<_segment::binary-size(body), next::binary>> -> jpeg_segments(next)
      _beyond_probe -> {:error, :media_unreadable}
    end
  end

  defp jpeg_segments(_other), do: {:error, :media_unreadable}

  # --- WebP ---------------------------------------------------------------

  # Lossy: frame tag (3 bytes), start code 9D 01 2A, then 14-bit sizes.
  defp webp(
         "VP8 ",
         <<_size::little-32, _tag::binary-size(3), 0x9D, 0x01, 0x2A, w::little-16, h::little-16,
           _::binary>>
       ),
       do: dimensions("image/webp", w &&& 0x3FFF, h &&& 0x3FFF)

  # Lossless: signature 0x2F, then 14-bit width-1 and height-1.
  defp webp("VP8L", <<_size::little-32, 0x2F, bits::little-32, _::binary>>) do
    width = (bits &&& 0x3FFF) + 1
    height = (bits >>> 14 &&& 0x3FFF) + 1
    dimensions("image/webp", width, height)
  end

  defp webp("VP8X", _rest), do: {:error, :media_has_metadata}
  defp webp(_chunk, _rest), do: {:error, :media_unreadable}

  defp dimensions(_type, width, height) when width <= 0 or height <= 0,
    do: {:error, :media_unreadable}

  defp dimensions(type, width, height),
    do: {:ok, %{content_type: type, width: width, height: height}}
end
