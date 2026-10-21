defmodule Palee.Wallet.Domain.PassImage do
  @moduledoc """
  Images of an Apple pass from the box's branding (ADR-155): the box's logo
  when it has a PNG one, and otherwise a plain tile in its primary colour, so
  every pass has the `icon.png` Apple requires. Pure (a tiny PNG encoder).
  """

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @default_color {17, 24, 39}

  @doc """
  The pass images: `icon.png`/`icon@2x.png` and `logo.png`/`logo@2x.png`.
  `logo` is the box's PNG logo bytes, or nil.
  """
  def images(primary_color, logo \\ nil) do
    color = parse_color(primary_color)

    tiles = %{
      "icon.png" => solid_png(29, 29, color),
      "icon@2x.png" => solid_png(58, 58, color)
    }

    if png?(logo),
      do: Map.merge(tiles, %{"logo.png" => logo, "logo@2x.png" => logo, "icon@3x.png" => logo}),
      else: Map.merge(tiles, %{"logo.png" => solid_png(50, 50, color)})
  end

  def png?(<<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>>), do: true
  def png?(_bytes), do: false

  @doc "A solid-colour RGB PNG."
  def solid_png(width, height, {r, g, b}) do
    row = <<0>> <> :binary.copy(<<r, g, b>>, width)
    data = :zlib.compress(:binary.copy(row, height))

    @png_signature <>
      chunk("IHDR", <<width::32, height::32, 8, 2, 0, 0, 0>>) <>
      chunk("IDAT", data) <>
      chunk("IEND", <<>>)
  end

  def parse_color("#" <> hex) when byte_size(hex) == 6 do
    case Integer.parse(hex, 16) do
      {value, ""} ->
        <<r, g, b>> = <<value::24>>
        {r, g, b}

      _invalid ->
        @default_color
    end
  end

  def parse_color(_color), do: @default_color

  defp chunk(type, data) do
    <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
  end
end
