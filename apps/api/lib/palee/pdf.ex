defmodule Palee.Pdf do
  @moduledoc """
  A small, deterministic PDF 1.7 writer (ADR-245): A4 pages with Unicode
  text in embedded TrueType fonts, filled and stroked rectangles and lines.
  Enough for fiscal documents and the Swiss QR-bill; no dependency, no
  network, no external process.

  Coordinates are PDF points (1/72 inch) from the **bottom-left** corner.
  Text is drawn with a `Palee.Pdf.TrueType` font as two-byte glyph ids
  (`Identity-H`); each font is embedded as a subset of the glyphs used, with
  a `ToUnicode` map so the text can be searched and copied. Content streams
  and fonts are Flate-compressed.

  The same calls always produce the same bytes (no clock, no random ids):
  the subset tag is derived from the glyphs used.

      Palee.Pdf.new(%{regular: font, bold: bold})
      |> Palee.Pdf.text(56.7, 780, "Τιμολόγιο I-000042", font: :bold, size: 16)
      |> Palee.Pdf.rect(56.7, 700, 100, 1, fill: true)
      |> Palee.Pdf.render(title: "I-000042")
  """

  alias Palee.Pdf.TrueType

  @a4 {595.28, 841.89}

  defstruct fonts: %{}, pages: [], current: [], used: %{}, texts: [], size: @a4

  @doc "A new document with one empty page. `fonts` maps a key to a parsed `TrueType` font."
  def new(fonts, opts \\ []) when is_map(fonts) do
    %__MODULE__{
      fonts: fonts,
      used: Map.new(fonts, fn {key, _font} -> {key, %{}} end),
      size: Keyword.get(opts, :size, @a4)
    }
  end

  def a4, do: @a4

  @doc "Starts a new page; drawing continues there."
  def add_page(%__MODULE__{} = pdf),
    do: %{pdf | pages: [pdf.current | pdf.pages], current: []}

  @doc "Number of pages so far."
  def page_count(%__MODULE__{pages: pages}), do: length(pages) + 1

  @doc """
  Draws `text` with its baseline at `{x, y}`. Options: `:font` (key, default
  `:regular`), `:size` (points, default 10), `:align` (`:left`, `:right` –
  `x` is then the right edge – or `:center`), `:color` (`{r, g, b}` 0..1).
  """
  def text(%__MODULE__{} = pdf, x, y, text, opts \\ []) do
    text = to_string(text)
    key = Keyword.get(opts, :font, :regular)
    size = Keyword.get(opts, :size, 10)
    font = Map.fetch!(pdf.fonts, key)

    if text == "" do
      pdf
    else
      width = TrueType.text_width(font, text, size)

      x =
        case Keyword.get(opts, :align, :left) do
          :right -> x - width
          :center -> x - width / 2
          :left -> x
        end

      {hex, used} =
        text
        |> String.to_charlist()
        |> Enum.map_reduce(pdf.used[key], fn codepoint, used ->
          # A no-break space prints as a space; a character the font lacks as "?".
          gid =
            case TrueType.glyph(font, if(codepoint == 0xA0, do: 0x20, else: codepoint)) do
              0 -> TrueType.glyph(font, 0x3F)
              gid -> gid
            end

          {hex4(gid), Map.put_new(used, gid, codepoint)}
        end)

      op = [
        color_op(Keyword.get(opts, :color), "rg"),
        "BT /",
        font_name(key),
        " ",
        num(size),
        " Tf ",
        num(x),
        " ",
        num(y),
        " Td <",
        hex,
        "> Tj ET\n"
      ]

      %{
        pdf
        | current: [op | pdf.current],
          used: Map.put(pdf.used, key, used),
          texts: [text | pdf.texts]
      }
    end
  end

  @doc "Width of `text` in points (for alignment and wrapping)."
  def text_width(%__MODULE__{} = pdf, text, opts \\ []) do
    font = Map.fetch!(pdf.fonts, Keyword.get(opts, :font, :regular))
    TrueType.text_width(font, to_string(text), Keyword.get(opts, :size, 10))
  end

  @doc """
  Splits `text` into lines no wider than `width` points (at word breaks;
  a single overlong word is cut).
  """
  def wrap(%__MODULE__{} = pdf, text, width, opts \\ []) do
    text
    |> to_string()
    |> String.split("\n")
    |> Enum.flat_map(fn paragraph ->
      paragraph
      |> String.split(" ", trim: true)
      |> Enum.reduce([], fn word, lines ->
        case lines do
          [] ->
            cut(pdf, word, width, opts)

          [line | rest] ->
            candidate = line <> " " <> word

            if text_width(pdf, candidate, opts) <= width,
              do: [candidate | rest],
              # `cut/4` returns its pieces last first, like `lines`.
              else: cut(pdf, word, width, opts) ++ lines
        end
      end)
      |> Enum.reverse()
      |> case do
        [] -> [""]
        lines -> lines
      end
    end)
  end

  defp cut(pdf, word, width, opts) do
    if text_width(pdf, word, opts) <= width do
      [word]
    else
      word
      |> String.graphemes()
      |> Enum.reduce([""], fn grapheme, [line | rest] ->
        if text_width(pdf, line <> grapheme, opts) <= width or line == "",
          do: [line <> grapheme | rest],
          else: [grapheme, line | rest]
      end)
    end
  end

  @doc """
  A rectangle with its lower-left corner at `{x, y}`. Options: `:fill`
  (default true), `:stroke`, `:color`, `:line_width`, `:dash`.
  """
  def rect(%__MODULE__{} = pdf, x, y, width, height, opts \\ []) do
    paint =
      case {Keyword.get(opts, :fill, true), Keyword.get(opts, :stroke, false)} do
        {true, true} -> "B"
        {true, false} -> "f"
        {false, _} -> "S"
      end

    op = [
      "q ",
      color_op(Keyword.get(opts, :color), if(paint == "S", do: "RG", else: "rg")),
      line_ops(opts),
      num(x),
      " ",
      num(y),
      " ",
      num(width),
      " ",
      num(height),
      " re ",
      paint,
      " Q\n"
    ]

    %{pdf | current: [op | pdf.current]}
  end

  @doc "A straight line. Options: `:color`, `:line_width` (default 0.5), `:dash` (`[on, off]`)."
  def line(%__MODULE__{} = pdf, x1, y1, x2, y2, opts \\ []) do
    op = [
      "q ",
      color_op(Keyword.get(opts, :color), "RG"),
      line_ops(Keyword.put_new(opts, :line_width, 0.5)),
      num(x1),
      " ",
      num(y1),
      " m ",
      num(x2),
      " ",
      num(y2),
      " l S Q\n"
    ]

    %{pdf | current: [op | pdf.current]}
  end

  @doc "Every text drawn so far, in drawing order (for tests and checks)."
  def texts(%__MODULE__{texts: texts}), do: Enum.reverse(texts)

  @doc "The PDF file. Options: `:title`, `:author`, `:created_at` (`DateTime`)."
  def render(%__MODULE__{} = pdf, info \\ []) do
    pages = Enum.reverse([pdf.current | pdf.pages])
    {width, height} = pdf.size
    page_count = length(pages)

    font_keys =
      pdf.used
      |> Enum.reject(fn {_key, used} -> used == %{} end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    # 1 catalog, 2 pages, 3 info, then per page (page, content), then per
    # font (type0, cid font, descriptor, font file, to-unicode).
    first_page = 4
    first_font = first_page + page_count * 2

    font_ids =
      font_keys
      |> Enum.with_index()
      |> Map.new(fn {key, index} -> {key, first_font + index * 5} end)

    resources = [
      "<< /Font << ",
      Enum.map(font_keys, fn key -> ["/", font_name(key), " ", ref(font_ids[key]), " "] end),
      ">> >>"
    ]

    page_objects =
      pages
      |> Enum.with_index()
      |> Enum.flat_map(fn {ops, index} ->
        page_id = first_page + index * 2

        [
          {page_id,
           [
             "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ",
             num(width),
             " ",
             num(height),
             "] /Resources ",
             resources,
             " /Contents ",
             ref(page_id + 1),
             " >>"
           ]},
          {page_id + 1, stream(ops |> Enum.reverse() |> IO.iodata_to_binary())}
        ]
      end)

    font_objects =
      Enum.flat_map(font_keys, fn key ->
        font_objects(font_ids[key], key, pdf.fonts[key], pdf.used[key])
      end)

    kids = Enum.map(0..(page_count - 1), fn index -> [ref(first_page + index * 2), " "] end)

    objects =
      [
        {1, "<< /Type /Catalog /Pages 2 0 R >>"},
        {2, ["<< /Type /Pages /Kids [", kids, "] /Count ", Integer.to_string(page_count), " >>"]},
        {3, info_dict(info)}
      ] ++ page_objects ++ font_objects

    write(objects)
  end

  # ── Fonts ─────────────────────────────────────────────────────────────────

  defp font_objects(id, key, font, used) do
    gids = used |> Map.keys() |> Enum.sort()
    tag = subset_tag(key, gids)
    base = "#{tag}+#{font.name}"
    scale = 1000 / font.units_per_em
    {x_min, y_min, x_max, y_max} = font.bbox
    program = TrueType.subset(font, gids)

    widths =
      Enum.map(gids, fn gid ->
        [Integer.to_string(gid), " [", num(TrueType.advance(font, gid) * scale), "] "]
      end)

    [
      {id,
       [
         "<< /Type /Font /Subtype /Type0 /BaseFont /",
         base,
         " /Encoding /Identity-H /DescendantFonts [",
         ref(id + 1),
         "] /ToUnicode ",
         ref(id + 4),
         " >>"
       ]},
      {id + 1,
       [
         "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /",
         base,
         " /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> ",
         "/FontDescriptor ",
         ref(id + 2),
         " /CIDToGIDMap /Identity /DW 1000 /W [",
         widths,
         "] >>"
       ]},
      {id + 2,
       [
         "<< /Type /FontDescriptor /FontName /",
         base,
         " /Flags 32 /FontBBox [",
         Enum.map_join([x_min, y_min, x_max, y_max], " ", &num(&1 * scale)),
         "] /ItalicAngle 0 /Ascent ",
         num(font.ascent * scale),
         " /Descent ",
         num(font.descent * scale),
         " /CapHeight ",
         num(font.cap_height * scale),
         " /StemV 80 /FontFile2 ",
         ref(id + 3),
         " >>"
       ]},
      {id + 3, stream(program, ["/Length1 ", Integer.to_string(byte_size(program))])},
      {id + 4, stream(to_unicode(used))}
    ]
  end

  defp to_unicode(used) do
    entries =
      used
      |> Enum.sort()
      |> Enum.chunk_every(100)
      |> Enum.map(fn chunk ->
        [
          Integer.to_string(length(chunk)),
          " beginbfchar\n",
          Enum.map(chunk, fn {gid, codepoint} ->
            ["<", hex4(gid), "> <", utf16_hex(codepoint), ">\n"]
          end),
          "endbfchar\n"
        ]
      end)

    IO.iodata_to_binary([
      "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n",
      "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n",
      "/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n",
      "1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n",
      entries,
      "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
    ])
  end

  defp utf16_hex(codepoint) do
    codepoint
    |> List.wrap()
    |> :unicode.characters_to_binary(:unicode, {:utf16, :big})
    |> Base.encode16()
  end

  defp subset_tag(key, gids) do
    :crypto.hash(:sha256, :erlang.term_to_binary({key, gids}))
    |> :binary.bin_to_list()
    |> Enum.take(6)
    |> Enum.map(&(?A + rem(&1, 26)))
    |> List.to_string()
  end

  # ── Writing ───────────────────────────────────────────────────────────────

  defp write(objects) do
    header = "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n"

    {bodies, offsets, _offset} =
      objects
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({[], [], byte_size(header)}, fn {id, body}, {bodies, offsets, offset} ->
        object = IO.iodata_to_binary([Integer.to_string(id), " 0 obj\n", body, "\nendobj\n"])
        {[object | bodies], [offset | offsets], offset + byte_size(object)}
      end)

    body = bodies |> Enum.reverse() |> IO.iodata_to_binary()
    xref_at = byte_size(header) + byte_size(body)
    size = length(objects) + 1

    xref = [
      "xref\n0 ",
      Integer.to_string(size),
      "\n0000000000 65535 f \n",
      offsets
      |> Enum.reverse()
      |> Enum.map(fn offset ->
        [offset |> Integer.to_string() |> String.pad_leading(10, "0"), " 00000 n \n"]
      end)
    ]

    IO.iodata_to_binary([
      header,
      body,
      xref,
      "trailer\n<< /Size ",
      Integer.to_string(size),
      " /Root 1 0 R /Info 3 0 R >>\nstartxref\n",
      Integer.to_string(xref_at),
      "\n%%EOF\n"
    ])
  end

  defp stream(data, extra \\ []) do
    compressed = :zlib.compress(data)

    [
      "<< /Length ",
      Integer.to_string(byte_size(compressed)),
      " /Filter /FlateDecode ",
      extra,
      " >>\nstream\n",
      compressed,
      "\nendstream"
    ]
  end

  defp info_dict(info) do
    fields =
      [
        {"Title", info[:title]},
        {"Author", info[:author]},
        {"Producer", "Palee"},
        {"CreationDate", info[:created_at] && pdf_date(info[:created_at])}
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map(fn {key, value} -> ["/", key, " ", text_string(value), " "] end)

    ["<< ", fields, ">>"]
  end

  defp pdf_date(%DateTime{} = at),
    do: "D:" <> Calendar.strftime(DateTime.shift_zone!(at, "Etc/UTC"), "%Y%m%d%H%M%SZ")

  # Info strings as UTF-16BE hex with a byte order mark.
  defp text_string(value) do
    [
      "<FEFF",
      value |> :unicode.characters_to_binary(:utf8, {:utf16, :big}) |> Base.encode16(),
      ">"
    ]
  end

  defp ref(id), do: [Integer.to_string(id), " 0 R"]

  defp font_name(key), do: "F" <> Atom.to_string(key)

  defp hex4(value), do: value |> Integer.to_string(16) |> String.pad_leading(4, "0")

  defp color_op(nil, _operator), do: []

  defp color_op({r, g, b}, operator),
    do: [num(r), " ", num(g), " ", num(b), " ", operator, " "]

  defp line_ops(opts) do
    [
      case Keyword.get(opts, :line_width) do
        nil -> []
        width -> [num(width), " w "]
      end,
      case Keyword.get(opts, :dash) do
        nil -> []
        [on, off] -> ["[", num(on), " ", num(off), "] 0 d "]
      end
    ]
  end

  @doc false
  def num(value) when is_integer(value), do: Integer.to_string(value)

  def num(value) when is_float(value) do
    rounded = Float.round(value, 3)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: :erlang.float_to_binary(rounded, [:compact, decimals: 3])
  end
end
