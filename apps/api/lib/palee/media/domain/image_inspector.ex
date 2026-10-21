defmodule Palee.Media.Domain.ImageInspector do
  @moduledoc """
  Reads the leading bytes of an uploaded image (ADR-148, ADR-157): its real type and
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

  @heic_brands ~w(heic heix hevc hevx heim heis)
  @heif_brands ~w(mif1 msf1 heif)
  @mp4_brands ["M4V " | ~w(isom iso2 iso4 iso5 iso6 mp41 mp42 avc1 dash 3gp4 3gp5 3gp6 MSNV)]

  @doc """
  The real type of an upload from its leading bytes (ADR-157), whatever the
  browser declared: `{:ok, content_type}` or `{:error, :invalid_media_type}`.
  Post uploads may still carry metadata; the server strips it.
  """
  def sniff(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "image/jpeg"}
  def sniff(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: {:ok, "image/png"}
  def sniff(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: {:ok, "image/webp"}
  def sniff(<<0x1A, 0x45, 0xDF, 0xA3, _rest::binary>>), do: {:ok, "video/webm"}

  def sniff(<<_size::binary-size(4), "ftyp", brand::binary-size(4), _rest::binary>>) do
    cond do
      brand in @heic_brands -> {:ok, "image/heic"}
      brand in @heif_brands -> {:ok, "image/heif"}
      brand == "qt  " -> {:ok, "video/quicktime"}
      brand in @mp4_brands -> {:ok, "video/mp4"}
      true -> {:error, :invalid_media_type}
    end
  end

  def sniff(_head), do: {:error, :invalid_media_type}

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
