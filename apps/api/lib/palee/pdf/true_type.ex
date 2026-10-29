defmodule Palee.Pdf.TrueType do
  @moduledoc """
  The parts of a TrueType font a PDF needs (ADR-245): character to glyph
  mapping (`cmap` format 4 and 12), advance widths, metrics, and a subset
  of the font that keeps only the glyphs a document uses.

  The subset keeps glyph numbering (unused glyphs become empty), so a PDF
  can address glyphs directly (`/CIDToGIDMap /Identity`), and keeps only the
  tables a PDF CIDFontType2 program needs (ISO 32000-1 §9.9): `head`,
  `hhea`, `maxp`, `hmtx`, `loca`, `glyf`, `cvt `, `fpgm`, `prep`.
  """

  import Bitwise

  defstruct [
    :name,
    :tables,
    :units_per_em,
    :bbox,
    :ascent,
    :descent,
    :cap_height,
    :num_glyphs,
    :advances,
    :cmap,
    :loca
  ]

  @subset_tables ["head", "hhea", "maxp", "hmtx", "loca", "glyf", "cvt ", "fpgm", "prep"]

  @doc "Parses a TrueType font file."
  def parse(
        <<_version::32, num_tables::16, _search::16, _selector::16, _shift::16, rest::binary>> =
          data
      ) do
    tables =
      for <<tag::binary-size(4), _checksum::32, offset::32,
            length::32 <-
              binary_part(
                rest,
                0,
                num_tables * 16
              )>>,
          into: %{},
          do: {tag, binary_part(data, offset, length)}

    <<_::binary-size(18), units_per_em::16, _::binary-size(16), x_min::16-signed,
      y_min::16-signed, x_max::16-signed, y_max::16-signed, _::binary-size(6),
      loca_format::16-signed, _::binary>> = tables["head"]

    <<_::binary-size(4), ascent::16-signed, descent::16-signed, _::binary-size(26),
      metrics_count::16, _::binary>> = tables["hhea"]

    <<_::binary-size(4), num_glyphs::16, _::binary>> = tables["maxp"]

    %__MODULE__{
      name: postscript_name(tables["name"]) || "Font",
      tables: tables,
      units_per_em: units_per_em,
      bbox: {x_min, y_min, x_max, y_max},
      ascent: ascent,
      descent: descent,
      cap_height: cap_height(tables["OS/2"]) || round(ascent * 0.7),
      num_glyphs: num_glyphs,
      advances: advances(tables["hmtx"], metrics_count, num_glyphs),
      cmap: cmap(tables["cmap"]),
      loca: loca(tables["loca"], loca_format, num_glyphs)
    }
  end

  @doc "The glyph of a code point (0, `.notdef`, when the font has none)."
  def glyph(%__MODULE__{cmap: cmap}, codepoint), do: Map.get(cmap, codepoint, 0)

  @doc "Advance width of a glyph in font units."
  def advance(%__MODULE__{advances: advances}, gid) when gid < tuple_size(advances),
    do: elem(advances, gid)

  def advance(%__MODULE__{advances: advances}, _gid),
    do: elem(advances, tuple_size(advances) - 1)

  @doc "Width of `text` at `size` points."
  def text_width(%__MODULE__{} = font, text, size) do
    units =
      text
      |> String.to_charlist()
      |> Enum.reduce(0, fn codepoint, acc -> acc + advance(font, glyph(font, codepoint)) end)

    units * size / font.units_per_em
  end

  @doc "A font program with only `gids` (and the glyphs they are built from)."
  def subset(%__MODULE__{} = font, gids) do
    glyf = font.tables["glyf"]
    keep = close_composites(font, MapSet.put(MapSet.new(gids), 0))

    {chunks, offsets, _offset} =
      Enum.reduce(0..(font.num_glyphs - 1), {[], [], 0}, fn gid, {chunks, offsets, offset} ->
        data = if MapSet.member?(keep, gid), do: glyph_data(font, glyf, gid), else: <<>>
        padded = pad4(data)
        {[padded | chunks], [offset | offsets], offset + byte_size(padded)}
      end)

    glyf_out = chunks |> Enum.reverse() |> IO.iodata_to_binary()

    loca_out =
      for offset <- Enum.reverse([byte_size(glyf_out) | offsets]), into: <<>>, do: <<offset::32>>

    <<head_start::binary-size(8), _adjustment::32, head_mid::binary-size(38), _format::16,
      head_rest::binary>> = font.tables["head"]

    head = <<head_start::binary, 0::32, head_mid::binary, 1::16, head_rest::binary>>

    font.tables
    |> Map.merge(%{"glyf" => glyf_out, "loca" => loca_out, "head" => head})
    |> Map.take(@subset_tables)
    |> build_font()
  end

  # ── Font file writing ─────────────────────────────────────────────────────

  defp build_font(tables) do
    tags = tables |> Map.keys() |> Enum.sort()
    count = length(tags)
    selector = count |> :math.log2() |> floor()
    search = (1 <<< selector) * 16
    header_size = 12 + count * 16

    {records, bodies, _offset} =
      Enum.reduce(tags, {[], [], header_size}, fn tag, {records, bodies, offset} ->
        body = tables[tag]
        record = <<tag::binary-size(4), checksum(body)::32, offset::32, byte_size(body)::32>>
        padded = pad4(body)
        {[record | records], [padded | bodies], offset + byte_size(padded)}
      end)

    IO.iodata_to_binary([
      <<0x00010000::32, count::16, search::16, selector::16, count * 16 - search::16>>,
      Enum.reverse(records),
      Enum.reverse(bodies)
    ])
  end

  defp checksum(body) do
    for <<word::32 <- pad4(body)>>, reduce: 0 do
      acc -> band(acc + word, 0xFFFFFFFF)
    end
  end

  defp pad4(data) do
    case rem(byte_size(data), 4) do
      0 -> data
      remainder -> data <> :binary.copy(<<0>>, 4 - remainder)
    end
  end

  # ── Glyphs ────────────────────────────────────────────────────────────────

  defp glyph_data(%{loca: loca}, glyf, gid) do
    from = elem(loca, gid)
    to = elem(loca, gid + 1)
    if to > from, do: binary_part(glyf, from, to - from), else: <<>>
  end

  defp close_composites(font, gids) do
    glyf = font.tables["glyf"]

    more =
      gids
      |> Enum.flat_map(&components(glyph_data(font, glyf, &1)))
      |> MapSet.new()
      |> MapSet.difference(gids)

    if MapSet.size(more) == 0, do: gids, else: close_composites(font, MapSet.union(gids, more))
  end

  defp components(<<contours::16-signed, _bbox::binary-size(8), rest::binary>>)
       when contours < 0,
       do: component_list(rest, [])

  defp components(_data), do: []

  defp component_list(<<flags::16, gid::16, rest::binary>>, acc) do
    args = if band(flags, 0x0001) != 0, do: 4, else: 2

    scale =
      cond do
        band(flags, 0x0008) != 0 -> 2
        band(flags, 0x0040) != 0 -> 4
        band(flags, 0x0080) != 0 -> 8
        true -> 0
      end

    <<_skip::binary-size(args + scale), rest::binary>> = rest
    acc = [gid | acc]
    if band(flags, 0x0020) != 0, do: component_list(rest, acc), else: acc
  end

  defp component_list(_data, acc), do: acc

  # ── Tables ────────────────────────────────────────────────────────────────

  defp advances(hmtx, metrics_count, num_glyphs) do
    metrics =
      for <<advance::16, _lsb::16 <- binary_part(hmtx, 0, metrics_count * 4)>>, do: advance

    last = List.last(metrics)
    List.to_tuple(metrics ++ List.duplicate(last, max(num_glyphs - metrics_count, 0)))
  end

  defp loca(loca, 0, num_glyphs),
    do:
      List.to_tuple(
        for <<offset::16 <- binary_part(loca, 0, (num_glyphs + 1) * 2)>>, do: offset * 2
      )

  defp loca(loca, 1, num_glyphs),
    do:
      List.to_tuple(for <<offset::32 <- binary_part(loca, 0, (num_glyphs + 1) * 4)>>, do: offset)

  defp cap_height(<<version::16, _::binary-size(86), cap::16-signed, _::binary>>)
       when version >= 2,
       do: cap

  defp cap_height(_os2), do: nil

  defp cmap(<<_version::16, count::16, rest::binary>> = table) do
    records =
      for <<platform::16, encoding::16, offset::32 <- binary_part(rest, 0, count * 8)>>,
        do: {platform, encoding, offset}

    pick =
      Enum.find(records, fn {p, e, _} -> p == 3 and e == 10 end) ||
        Enum.find(records, fn {p, e, _} -> p == 3 and e == 1 end) ||
        Enum.find(records, fn {p, _e, _} -> p == 0 end)

    case pick do
      {_p, _e, offset} -> subtable(binary_part(table, offset, byte_size(table) - offset))
      nil -> %{}
    end
  end

  defp subtable(
         <<4::16, length::16, _language::16, seg_x2::16, _::binary-size(6), _::binary>> =
           data
       ) do
    data = binary_part(data, 0, min(length, byte_size(data)))
    segments = div(seg_x2, 2)
    ends = words(data, 14, segments)
    starts = words(data, 16 + seg_x2, segments)
    deltas = words(data, 16 + 2 * seg_x2, segments)
    range_base = 16 + 3 * seg_x2
    ranges = words(data, range_base, segments)

    [ends, starts, deltas, ranges]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{last, first, delta, range}, index}, acc ->
      Enum.reduce(first..last//1, acc, fn code, acc ->
        gid =
          if range == 0 do
            band(code + delta, 0xFFFF)
          else
            at = range_base + index * 2 + range + (code - first) * 2

            case data do
              <<_::binary-size(at), value::16, _::binary>> when value != 0 ->
                band(value + delta, 0xFFFF)

              _ ->
                0
            end
          end

        if code == 0xFFFF or gid == 0, do: acc, else: Map.put(acc, code, gid)
      end)
    end)
  end

  defp subtable(<<12::16, _reserved::16, _length::32, _language::32, groups::32, rest::binary>>) do
    for <<first::32, last::32, start_gid::32 <- binary_part(rest, 0, groups * 12)>>,
        code <- first..last//1,
        into: %{},
        do: {code, start_gid + code - first}
  end

  defp subtable(_data), do: %{}

  defp words(data, offset, count),
    do: for(<<word::16 <- binary_part(data, offset, count * 2)>>, do: word)

  # PostScript name (name id 6), Windows Unicode or Mac Roman.
  defp postscript_name(nil), do: nil

  defp postscript_name(<<_format::16, count::16, storage::16, rest::binary>> = table) do
    records =
      for <<platform::16, _encoding::16, _language::16, name_id::16, length::16,
            offset::16 <-
              binary_part(rest, 0, count * 12)>>,
          name_id == 6,
          do: {platform, binary_part(table, storage + offset, length)}

    case Enum.find(records, fn {platform, _} -> platform == 3 end) do
      {3, value} ->
        :unicode.characters_to_binary(value, {:utf16, :big})

      nil ->
        case records do
          [{_platform, value} | _] -> value
          [] -> nil
        end
    end
  end
end
