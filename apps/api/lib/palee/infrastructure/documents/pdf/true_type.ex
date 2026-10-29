defmodule Palee.Infrastructure.Documents.Pdf.TrueType do
  @moduledoc """
  The little of TrueType a PDF writer needs (ADR-252): character to glyph
  mapping (`cmap` formats 4 and 12), advance widths, the metrics for the
  font descriptor, and a **subset** keeping only the glyphs a document
  uses (plus the components of composite glyphs), so a certificate embeds
  a few kilobytes of font instead of the whole file.

  The subset keeps glyph ids unchanged (unused glyphs become empty), so the
  PDF can use `CIDToGIDMap /Identity`. Only the tables a PDF reader needs
  for a CIDFontType2 are kept: `cvt `, `fpgm`, `glyf`, `head`, `hhea`,
  `hmtx`, `loca`, `maxp` and `prep`.
  """

  import Bitwise

  defstruct [
    :tables,
    :units_per_em,
    :bbox,
    :ascent,
    :descent,
    :cap_height,
    :num_glyphs,
    :advances,
    :cmap,
    :index_to_loc_format
  ]

  @kept_tables ["cvt ", "fpgm", "glyf", "head", "hhea", "hmtx", "loca", "maxp", "prep"]

  @doc "Parses a TrueType (glyf-outline) font."
  def parse(<<0x00010000::32, num_tables::16, _search::48, rest::binary>> = font) do
    tables =
      for <<tag::binary-size(4), _checksum::32, offset::32, length::32 <- binary_part(
              rest,
              0,
              num_tables * 16
            )>>,
          into: %{} do
        {tag, binary_part(font, offset, length)}
      end

    <<_::binary-size(18), units_per_em::16, _::binary-size(16), x_min::signed-16,
      y_min::signed-16, x_max::signed-16, y_max::signed-16, _::binary-size(6),
      index_to_loc_format::signed-16, _::binary>> = tables["head"]

    <<_::binary-size(4), ascent::signed-16, descent::signed-16, _::binary-size(26),
      num_h_metrics::16, _::binary>> = tables["hhea"]

    <<_::binary-size(4), num_glyphs::16, _::binary>> = tables["maxp"]

    %__MODULE__{
      tables: tables,
      units_per_em: units_per_em,
      bbox: {x_min, y_min, x_max, y_max},
      ascent: ascent,
      descent: descent,
      cap_height: cap_height(tables["OS/2"], ascent),
      num_glyphs: num_glyphs,
      advances: advances(tables["hmtx"], num_h_metrics, num_glyphs),
      cmap: cmap(tables["cmap"]),
      index_to_loc_format: index_to_loc_format
    }
  end

  defp cap_height(<<version::16, _::binary-size(86), cap::signed-16, _::binary>>, _ascent)
       when version >= 2,
       do: cap

  defp cap_height(_os2, ascent), do: round(ascent * 0.7)

  defp advances(hmtx, num_h_metrics, num_glyphs) do
    long = for <<advance::16, _lsb::16 <- binary_part(hmtx, 0, num_h_metrics * 4)>>, do: advance
    last = List.last(long)
    List.to_tuple(long ++ List.duplicate(last, num_glyphs - num_h_metrics))
  end

  # ── cmap ──────────────────────────────────────────────────────────────────

  # A subset (what PDF embeds) has no cmap: glyphs are addressed by id.
  defp cmap(nil), do: %{}

  defp cmap(<<_version::16, count::16, rest::binary>> = table) do
    records =
      for <<platform::16, encoding::16, offset::32 <- binary_part(rest, 0, count * 8)>>,
        do: {platform, encoding, offset}

    preferred =
      Enum.find(records, &match?({3, 10, _}, &1)) || Enum.find(records, &match?({0, 4, _}, &1)) ||
        Enum.find(records, &match?({3, 1, _}, &1)) || Enum.find(records, &match?({0, _, _}, &1))

    case preferred do
      {_platform, _encoding, offset} -> subtable(binary_part(table, offset, byte_size(table) - offset))
      nil -> %{}
    end
  end

  defp subtable(<<12::16, _reserved::16, _length::32, _language::32, groups::32, rest::binary>>) do
    for <<start::32, stop::32, glyph::32 <- binary_part(rest, 0, groups * 12)>>,
        code <- start..stop,
        into: %{},
        do: {code, glyph + code - start}
  end

  defp subtable(<<4::16, _length::16, _language::16, seg_x2::16, _::binary-size(6), rest::binary>>) do
    <<ends::binary-size(seg_x2), _pad::16, starts::binary-size(seg_x2), deltas::binary-size(seg_x2),
      range_area::binary>> = rest

    ends = for <<v::16 <- ends>>, do: v
    starts = for <<v::16 <- starts>>, do: v
    deltas = for <<v::16 <- deltas>>, do: v
    ranges = for <<v::16 <- binary_part(range_area, 0, seg_x2)>>, do: v

    [ends, starts, deltas, ranges]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{stop, start, delta, range}, index}, acc ->
      Enum.reduce(start..stop//1, acc, fn code, acc ->
        glyph = format4_glyph(code, start, delta, range, index, range_area)
        if code != 0xFFFF and glyph != 0, do: Map.put(acc, code, glyph), else: acc
      end)
    end)
  end

  defp subtable(_other), do: %{}

  defp format4_glyph(code, _start, delta, 0, _index, _area), do: band(code + delta, 0xFFFF)

  defp format4_glyph(code, start, delta, range, index, area) do
    position = index * 2 + range + (code - start) * 2

    case area do
      <<_::binary-size(position), 0::16, _::binary>> -> 0
      <<_::binary-size(position), glyph::16, _::binary>> -> band(glyph + delta, 0xFFFF)
      _ -> 0
    end
  end

  # ── Metrics ───────────────────────────────────────────────────────────────

  @doc "The glyph id of a codepoint (0, `.notdef`, when the font lacks it)."
  def glyph(%__MODULE__{cmap: cmap}, codepoint), do: Map.get(cmap, codepoint, 0)

  @doc "Advance width of a glyph in font units."
  def advance(%__MODULE__{advances: advances}, glyph) when glyph < tuple_size(advances),
    do: elem(advances, glyph)

  def advance(%__MODULE__{advances: advances}, _glyph), do: elem(advances, 0)

  @doc "Width of `text` at `size` points."
  def text_width(%__MODULE__{} = font, text, size) do
    units =
      text
      |> String.to_charlist()
      |> Enum.reduce(0, fn codepoint, sum -> sum + advance(font, glyph(font, codepoint)) end)

    units * size / font.units_per_em
  end

  @doc "Font units scaled to the PDF glyph space (1000 per em)."
  def scale(%__MODULE__{units_per_em: units}, value), do: round(value * 1000 / units)

  # ── Subset ────────────────────────────────────────────────────────────────

  @doc "A TrueType file with only `glyphs` (and `.notdef`, and their components)."
  def subset(%__MODULE__{tables: tables} = font, glyphs) do
    offsets = loca(font)
    glyf = tables["glyf"]
    keep = closure(MapSet.new([0 | Enum.to_list(glyphs)]), glyf, offsets)

    {glyf_data, locations} =
      Enum.reduce(0..(font.num_glyphs - 1), {[], [0]}, fn glyph, {data, [last | _] = locations} ->
        bytes =
          if MapSet.member?(keep, glyph), do: glyph_data(glyf, offsets, glyph), else: <<>>

        padded = pad(bytes)
        {[padded | data], [last + byte_size(padded) | locations]}
      end)

    new_glyf = glyf_data |> Enum.reverse() |> IO.iodata_to_binary()
    new_loca = for offset <- Enum.reverse(locations), into: <<>>, do: <<offset::32>>

    <<head_start::binary-size(8), _adjustment::32, head_middle::binary-size(38), _format::16,
      head_rest::binary>> = tables["head"]

    head = <<head_start::binary, 0::32, head_middle::binary, 1::16, head_rest::binary>>

    replaced = Map.merge(tables, %{"glyf" => new_glyf, "loca" => new_loca, "head" => head})

    @kept_tables
    |> Enum.filter(&Map.has_key?(replaced, &1))
    |> Enum.map(&{&1, Map.fetch!(replaced, &1)})
    |> assemble()
  end

  defp loca(%__MODULE__{tables: %{"loca" => loca}, index_to_loc_format: 0}),
    do: List.to_tuple(for <<offset::16 <- loca>>, do: offset * 2)

  defp loca(%__MODULE__{tables: %{"loca" => loca}}),
    do: List.to_tuple(for <<offset::32 <- loca>>, do: offset)

  defp glyph_data(glyf, offsets, glyph) do
    start = elem(offsets, glyph)
    stop = elem(offsets, glyph + 1)
    binary_part(glyf, start, stop - start)
  end

  defp closure(keep, glyf, offsets) do
    components =
      keep
      |> Enum.flat_map(fn glyph -> components(glyph_data(glyf, offsets, glyph)) end)
      |> MapSet.new()

    if MapSet.subset?(components, keep),
      do: keep,
      else: closure(MapSet.union(keep, components), glyf, offsets)
  end

  # Composite glyphs (negative contour count) name their component glyphs.
  defp components(<<contours::signed-16, _bbox::binary-size(8), rest::binary>>)
       when contours < 0,
       do: composite(rest, [])

  defp components(_simple), do: []

  defp composite(<<flags::16, glyph::16, rest::binary>>, acc) do
    args = if band(flags, 0x0001) != 0, do: 4, else: 2

    transform =
      cond do
        band(flags, 0x0008) != 0 -> 2
        band(flags, 0x0040) != 0 -> 4
        band(flags, 0x0080) != 0 -> 8
        true -> 0
      end

    <<_::binary-size(args + transform), next::binary>> = rest

    if band(flags, 0x0020) != 0,
      do: composite(next, [glyph | acc]),
      else: [glyph | acc]
  end

  defp composite(_rest, acc), do: acc

  defp pad(bytes) do
    case rem(byte_size(bytes), 4) do
      0 -> bytes
      remainder -> bytes <> :binary.copy(<<0>>, 4 - remainder)
    end
  end

  defp assemble(tables) do
    count = length(tables)
    entry_selector = count |> :math.log2() |> floor()
    search_range = Integer.pow(2, entry_selector) * 16
    header_size = 12 + count * 16

    {records, data, _offset} =
      Enum.reduce(tables, {[], [], header_size}, fn {tag, bytes}, {records, data, offset} ->
        padded = pad(bytes)
        record = <<tag::binary, checksum(padded)::32, offset::32, byte_size(bytes)::32>>
        {[record | records], [padded | data], offset + byte_size(padded)}
      end)

    font =
      IO.iodata_to_binary([
        <<0x00010000::32, count::16, search_range::16, entry_selector::16,
          count * 16 - search_range::16>>,
        Enum.reverse(records),
        Enum.reverse(data)
      ])

    adjustment = band(0xB1B0AFBA - checksum(font), 0xFFFFFFFF)
    {head_offset, _length} = head_location(font, count)

    <<before::binary-size(head_offset + 8), _zero::32, after_adjustment::binary>> = font
    <<before::binary, adjustment::32, after_adjustment::binary>>
  end

  defp head_location(font, count) do
    for <<tag::binary-size(4), _checksum::32, offset::32, length::32 <-
            binary_part(font, 12, count * 16)>>,
        tag == "head",
        reduce: nil do
      _ -> {offset, length}
    end
  end

  defp checksum(bytes) do
    padded = pad(bytes)
    sum = for <<word::32 <- padded>>, reduce: 0, do: (acc -> acc + word)
    band(sum, 0xFFFFFFFF)
  end
end
