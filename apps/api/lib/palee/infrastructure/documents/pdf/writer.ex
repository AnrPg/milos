defmodule Palee.Infrastructure.Documents.Pdf.Writer do
  @moduledoc """
  A minimal PDF 1.7 writer for the signature certificates (ADR-252).

  The stack has no PDF library (receipts are printable HTML, invoices are
  drawn in the browser with jsPDF), and a certificate must be produced and
  stored on the server at signing time. What it needs is small: pages of
  text in one Unicode font (Greek included) and a few vector strokes. So
  this writer embeds a subset of DejaVu Sans as a `Type0`/`CIDFontType2`
  font with `Identity-H` encoding and a `ToUnicode` map (text can be
  searched and copied), and compresses every stream.

  Input is a list of pages; each page is a list of operations:

    * `{:text, x, y, size, string}` – one line of text (no wrapping here);
    * `{:polyline, [{x, y}, ...], width}` – a stroked line;
    * `{:rect, x, y, w, h, width}` – a stroked rectangle.

  Coordinates are PDF points from the bottom-left corner. The output is
  deterministic: the same input gives the same bytes.
  """

  alias Palee.Infrastructure.Documents.Pdf.TrueType

  @page_width 595.28
  @page_height 841.89
  @font_name "DejaVuSans"

  def page_size, do: {@page_width, @page_height}

  @doc "The parsed font (cached for the life of the VM)."
  def font do
    case :persistent_term.get({__MODULE__, :font}, nil) do
      nil ->
        font =
          :palee
          |> :code.priv_dir()
          |> Path.join("fonts/DejaVuSans.ttf")
          |> File.read!()
          |> TrueType.parse()

        :persistent_term.put({__MODULE__, :font}, font)
        font

      font ->
        font
    end
  end

  @doc """
  Renders `pages` to a PDF binary. `info` may hold `:title`, `:subject`,
  `:created_at` (a `DateTime`) and `:id` (a hex string for the file id).
  """
  def render(pages, info \\ %{}) when is_list(pages) and pages != [] do
    font = font()
    glyphs = used_glyphs(font, pages)

    page_count = length(pages)
    # Objects: 1 catalog, 2 pages, 3 info, 4 font, 5 cid font, 6 descriptor,
    # 7 font file, 8 to-unicode, then a page and its content per page.
    first_page = 9
    page_ids = Enum.map(0..(page_count - 1), &(first_page + &1 * 2))

    objects =
      [
        {1, "<< /Type /Catalog /Pages 2 0 R >>"},
        {2,
         "<< /Type /Pages /Count #{page_count} /Kids [#{Enum.map_join(page_ids, " ", &"#{&1} 0 R")}] >>"},
        {3, info_dictionary(info)},
        {4,
         "<< /Type /Font /Subtype /Type0 /BaseFont /#{subset_tag(glyphs)}+#{@font_name} " <>
           "/Encoding /Identity-H /DescendantFonts [5 0 R] /ToUnicode 8 0 R >>"},
        {5,
         "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /#{subset_tag(glyphs)}+#{@font_name} " <>
           "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> " <>
           "/FontDescriptor 6 0 R /DW #{TrueType.scale(font, TrueType.advance(font, 0))} " <>
           "/W #{widths(font, glyphs)} /CIDToGIDMap /Identity >>"},
        {6, descriptor(font, glyphs)},
        {7, font_file(font, glyphs)},
        {8, stream(to_unicode(glyphs))}
      ] ++
        Enum.flat_map(Enum.zip(page_ids, pages), fn {page_id, operations} ->
          [
            {page_id,
             "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{num(@page_width)} #{num(@page_height)}] " <>
               "/Resources << /Font << /F1 4 0 R >> >> /Contents #{page_id + 1} 0 R >>"},
            {page_id + 1, stream(content(font, operations))}
          ]
        end)

    assemble(objects, info)
  end

  # ── Glyphs ────────────────────────────────────────────────────────────────

  defp used_glyphs(font, pages) do
    pages
    |> List.flatten()
    |> Enum.flat_map(fn
      {:text, _x, _y, _size, text} -> String.to_charlist(text)
      _other -> []
    end)
    |> Enum.uniq()
    |> Map.new(fn codepoint -> {TrueType.glyph(font, codepoint), codepoint} end)
    |> Map.delete(0)
  end

  defp subset_tag(glyphs) do
    glyphs
    |> Map.keys()
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> :binary.bin_to_list()
    |> Enum.take(6)
    |> Enum.map(&(?A + rem(&1, 26)))
    |> List.to_string()
  end

  defp widths(font, glyphs) do
    entries =
      glyphs
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join(" ", fn glyph ->
        "#{glyph} [#{TrueType.scale(font, TrueType.advance(font, glyph))}]"
      end)

    "[#{entries}]"
  end

  defp descriptor(font, glyphs) do
    {x_min, y_min, x_max, y_max} = font.bbox
    bbox = Enum.map_join([x_min, y_min, x_max, y_max], " ", &TrueType.scale(font, &1))

    "<< /Type /FontDescriptor /FontName /#{subset_tag(glyphs)}+#{@font_name} /Flags 32 " <>
      "/FontBBox [#{bbox}] /ItalicAngle 0 /Ascent #{TrueType.scale(font, font.ascent)} " <>
      "/Descent #{TrueType.scale(font, font.descent)} " <>
      "/CapHeight #{TrueType.scale(font, font.cap_height)} /StemV 80 /FontFile2 7 0 R >>"
  end

  defp font_file(font, glyphs) do
    subset = TrueType.subset(font, Map.keys(glyphs))
    stream(subset, "/Length1 #{byte_size(subset)}")
  end

  defp to_unicode(glyphs) do
    mappings =
      glyphs
      |> Enum.sort()
      |> Enum.chunk_every(100)
      |> Enum.map_join("\n", fn chunk ->
        lines =
          Enum.map_join(chunk, "\n", fn {glyph, codepoint} ->
            "<#{hex16(glyph)}> <#{utf16_hex(codepoint)}>"
          end)

        "#{length(chunk)} beginbfchar\n#{lines}\nendbfchar"
      end)

    """
    /CIDInit /ProcSet findresource begin
    12 dict begin
    begincmap
    /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
    /CMapName /Adobe-Identity-UCS def
    /CMapType 2 def
    1 begincodespacerange
    <0000> <FFFF>
    endcodespacerange
    #{mappings}
    endcmap
    CMapName currentdict /CMap defineresource pop
    end
    end
    """
  end

  defp utf16_hex(codepoint) do
    <<codepoint::utf16>>
    |> Base.encode16()
  end

  defp hex16(value), do: value |> Integer.to_string(16) |> String.pad_leading(4, "0")

  # ── Content ───────────────────────────────────────────────────────────────

  defp content(font, operations) do
    operations
    |> Enum.map(&operation(font, &1))
    |> Enum.join("\n")
  end

  defp operation(font, {:text, x, y, size, text}) do
    glyphs =
      text
      |> String.to_charlist()
      |> Enum.map_join(fn codepoint -> hex16(TrueType.glyph(font, codepoint)) end)

    "BT /F1 #{num(size)} Tf #{num(x)} #{num(y)} Td <#{glyphs}> Tj ET"
  end

  defp operation(_font, {:polyline, [{x, y} | rest], width}) do
    lines = Enum.map_join(rest, " ", fn {lx, ly} -> "#{num(lx)} #{num(ly)} l" end)
    "#{num(width)} w 1 J 1 j #{num(x)} #{num(y)} m #{lines} S"
  end

  defp operation(_font, {:polyline, _points, _width}), do: ""

  defp operation(_font, {:rect, x, y, w, h, width}),
    do: "#{num(width)} w #{num(x)} #{num(y)} #{num(w)} #{num(h)} re S"

  # ── File ──────────────────────────────────────────────────────────────────

  defp info_dictionary(info) do
    entries =
      [
        {"Producer", "Palee"},
        {"Title", info[:title]},
        {"Subject", info[:subject]},
        {"CreationDate", info[:created_at] && pdf_date(info[:created_at])}
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join(" ", fn {key, value} -> "/#{key} #{text_string(value)}" end)

    "<< #{entries} >>"
  end

  defp pdf_date(%DateTime{} = at) do
    at = DateTime.shift_zone!(at, "Etc/UTC")
    "D:" <> Calendar.strftime(at, "%Y%m%d%H%M%S") <> "Z"
  end

  # Text strings as UTF-16BE with a byte order mark (any language).
  defp text_string(value) do
    hex =
      value
      |> :unicode.characters_to_binary(:utf8, {:utf16, :big})
      |> Base.encode16()

    "<FEFF#{hex}>"
  end

  defp stream(data, extra \\ "") do
    compressed = :zlib.compress(data)
    {:stream, "<< /Length #{byte_size(compressed)} /Filter /FlateDecode #{extra}>>", compressed}
  end

  defp assemble(objects, info) do
    header = "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n"

    {chunks, offsets, _size} =
      Enum.reduce(objects, {[header], %{}, byte_size(header)}, fn {id, body},
                                                                    {chunks, offsets, size} ->
        bytes = object(id, body)
        {[bytes | chunks], Map.put(offsets, id, size), size + byte_size(bytes)}
      end)

    count = map_size(offsets) + 1
    xref_offset = chunks |> Enum.map(&byte_size/1) |> Enum.sum()

    xref =
      ["xref\n0 #{count}\n0000000000 65535 f \n"] ++
        Enum.map(1..(count - 1), fn id ->
          (offsets |> Map.fetch!(id) |> Integer.to_string() |> String.pad_leading(10, "0")) <>
            " 00000 n \n"
        end)

    file_id = info[:id] || :crypto.hash(:md5, Enum.reverse(chunks)) |> Base.encode16()

    trailer =
      "trailer\n<< /Size #{count} /Root 1 0 R /Info 3 0 R /ID [<#{file_id}> <#{file_id}>] >>\n" <>
        "startxref\n#{xref_offset}\n%%EOF\n"

    IO.iodata_to_binary([Enum.reverse(chunks), xref, trailer])
  end

  defp object(id, {:stream, dictionary, data}),
    do: IO.iodata_to_binary(["#{id} 0 obj\n", dictionary, "\nstream\n", data, "\nendstream\nendobj\n"])

  defp object(id, body), do: "#{id} 0 obj\n#{body}\nendobj\n"

  defp num(value) when is_integer(value), do: Integer.to_string(value)

  defp num(value) when is_float(value),
    do: :erlang.float_to_binary(Float.round(value, 2), [:compact, decimals: 2])
end
