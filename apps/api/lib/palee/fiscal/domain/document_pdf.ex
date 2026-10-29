defmodule Palee.Fiscal.Domain.DocumentPdf do
  @moduledoc """
  A fiscal document as an A4 PDF (ADR-245), drawn from a `DocumentView`
  with `Palee.Pdf` and embedded Liberation Sans (Latin, Greek; one of the
  fonts the QR-bill allows).

  Layout: header (title, number, dates), seller and buyer, the lines (the
  table continues on new pages), VAT breakdown, totals, legal mentions,
  the authority block with its QR code, bank details and the fingerprint.
  A Swiss QR-bill gets its own page with the slip at the bottom edge per
  SIX IG v2.4 §3: 210 × 105 mm, receipt 62 mm with 11 pt title, 6 pt
  headings and 8 pt values, payment part 148 mm with 11 pt title, 8 pt
  headings and 10 pt values, the 46 × 46 mm QR code 5 mm from its
  edges with the 7 mm Swiss cross, the amount and debtor boxes when those
  are not printed, and dashed separation lines with "Separate before
  paying in".
  """

  alias Palee.Pdf

  @mm 72 / 25.4
  @page_height 297
  @left 18
  @right 192
  @bottom 22
  @line 4.6

  @doc "The PDF bytes of `view`. `fonts` is `Palee.Pdf.Fonts.sans/0`."
  def render(view, fonts, opts \\ []) do
    view
    |> layout(fonts)
    |> Pdf.render(
      title: "#{view.title} #{view.number}",
      author: view.seller.name,
      created_at: Keyword.get(opts, :created_at)
    )
  end

  @doc "The texts a render draws, in order (for checks without parsing the PDF)."
  def texts(view, fonts), do: view |> layout(fonts) |> Pdf.texts()

  defp layout(view, fonts) do
    %{pdf: Pdf.new(fonts), y: 18, page: 1, view: view}
    |> header()
    |> parties()
    |> table()
    |> breakdown()
    |> totals()
    |> mentions()
    |> authority()
    |> bank()
    |> footer()
    |> qr_bill()
    |> Map.fetch!(:pdf)
  end

  # ── Sections ──────────────────────────────────────────────────────────────

  defp header(%{view: view} = s) do
    title_lines = Pdf.wrap(s.pdf, view.title, mm(100), font: :bold, size: 16)

    s =
      title_lines
      |> Enum.with_index()
      |> Enum.reduce(s, fn {line, index}, s ->
        text(s, @left, s.y + 6 + index * 7, line, font: :bold, size: 16)
      end)

    meta_y = s.y + 3

    s =
      view.meta
      |> Enum.with_index()
      |> Enum.reduce(s, fn {{term, value}, index}, s ->
        y = meta_y + index * 4.4

        s
        |> text(150, y, term, size: 8.5, align: :right, color: {0.3, 0.3, 0.3})
        |> text(@right, y, value, font: :bold, size: 8.5, align: :right)
      end)

    bottom = max(s.y + 6 + length(title_lines) * 7, meta_y + length(view.meta) * 4.4) + 1
    s = %{s | y: bottom}
    s = hline(s, s.y, 1.2)
    %{s | y: s.y + 6}
  end

  defp parties(%{view: view} = s) do
    top = s.y
    {s, seller_y} = party(s, @left, top, view.seller_heading, view.seller)

    {s, buyer_y} =
      if view.buyer, do: party(s, 110, top, view.buyer_heading, view.buyer), else: {s, top}

    %{s | y: max(seller_y, buyer_y) + 4}
  end

  defp party(s, x, top, heading, party) do
    s = text(s, x, top, String.upcase(heading), size: 7.5, color: {0.3, 0.3, 0.3})
    s = text(s, x, top + 4.5, party.name, font: :bold, size: 10)

    rows =
      party.lines ++
        Enum.map(party.ids, fn {term, value} -> "#{term}: #{value}" end) ++ party.contact

    rows
    |> Enum.flat_map(&Pdf.wrap(s.pdf, &1, mm(78), size: 9))
    |> Enum.with_index()
    |> Enum.reduce({s, top + 4.5}, fn {row, index}, {s, _y} ->
      y = top + 9 + index * 4
      {text(s, x, y, row, size: 9), y}
    end)
  end

  defp columns(view) do
    if view.show_discount,
      do: %{desc_width: 82, quantity: 112, unit: 137, discount: 157, rate: 170, amount: @right},
      else: %{desc_width: 92, quantity: 122, unit: 150, discount: nil, rate: 166, amount: @right}
  end

  defp table(%{view: view} = s) do
    s = table_head(s)

    Enum.reduce(view.lines, s, fn line, s ->
      cols = columns(view)
      description = Pdf.wrap(s.pdf, line.description, mm(cols.desc_width), size: 9)

      note =
        if line.note, do: Pdf.wrap(s.pdf, line.note, mm(cols.desc_width), size: 7.5), else: []

      height = length(description) * @line + length(note) * 3.6 + 1.5
      s = ensure(s, height, &table_head/1)
      y = s.y + 3.6

      s =
        description
        |> Enum.with_index()
        |> Enum.reduce(s, fn {row, index}, s ->
          text(s, @left, y + index * @line, row, size: 9)
        end)

      note_y = y + length(description) * @line - 0.8

      s =
        note
        |> Enum.with_index()
        |> Enum.reduce(s, fn {row, index}, s ->
          text(s, @left, note_y + index * 3.6, row, size: 7.5, color: {0.3, 0.3, 0.3})
        end)

      s =
        s
        |> text(cols.quantity, y, line.quantity, size: 9, align: :right)
        |> text(cols.unit, y, line.unit_price, size: 9, align: :right)
        |> then(fn s ->
          if cols.discount,
            do: text(s, cols.discount, y, line.discount, size: 9, align: :right),
            else: s
        end)
        |> text(cols.rate, y, line.rate, size: 9, align: :right)
        |> text(cols.amount, y, line.amount, size: 9, align: :right)

      s = %{s | y: s.y + height}
      hline(s, s.y - 0.4, 0.25, {0.75, 0.75, 0.75})
    end)
  end

  defp table_head(%{view: view} = s) do
    c = view.columns
    cols = columns(view)
    y = s.y + 3

    s =
      s
      |> text(@left, y, c.description, font: :bold, size: 8)
      |> text(cols.quantity, y, c.quantity, font: :bold, size: 8, align: :right)
      |> text(cols.unit, y, c.unit_price, font: :bold, size: 8, align: :right)
      |> then(fn s ->
        if cols.discount,
          do: text(s, cols.discount, y, c.discount, font: :bold, size: 8, align: :right),
          else: s
      end)
      |> text(cols.rate, y, c.rate, font: :bold, size: 8, align: :right)
      |> text(cols.amount, y, c.amount, font: :bold, size: 8, align: :right)

    s = hline(s, y + 1.4, 0.75)
    %{s | y: y + 2}
  end

  defp breakdown(%{view: view} = s) do
    s = ensure(s, 12 + length(view.breakdown) * 4.4, & &1)
    s = %{s | y: s.y + 6}

    s =
      text(s, @left, s.y, String.upcase(view.breakdown_heading),
        size: 7.5,
        color: {0.3, 0.3, 0.3}
      )

    xs = [@left, 70, 95, 120]
    y = s.y + 4.5

    s =
      view.breakdown_columns
      |> Enum.zip(xs)
      |> Enum.with_index()
      |> Enum.reduce(s, fn {{column, x}, index}, s ->
        if index == 0,
          do: text(s, x, y, column, font: :bold, size: 8),
          else: text(s, x, y, column, font: :bold, size: 8, align: :right)
      end)

    s = hline(s, y + 1.2, 0.5, nil, 120)

    s =
      view.breakdown
      |> Enum.with_index()
      |> Enum.reduce(s, fn {row, index}, s ->
        row_y = y + 5 + index * 4.4

        row
        |> Enum.zip(xs)
        |> Enum.with_index()
        |> Enum.reduce(s, fn {{value, x}, column}, s ->
          if column == 0,
            do: text(s, x, row_y, value, size: 9),
            else: text(s, x, row_y, value, size: 9, align: :right)
        end)
      end)

    %{s | y: y + 5 + length(view.breakdown) * 4.4}
  end

  defp totals(%{view: view} = s) do
    s = ensure(s, 6 + length(view.totals) * 5.5, & &1)
    y = s.y + 2

    s =
      view.totals
      |> Enum.with_index()
      |> Enum.reduce(s, fn {{term, value, strong?}, index}, s ->
        row_y = y + index * 5.5
        opts = if strong?, do: [font: :bold, size: 11], else: [size: 9.5]

        s
        |> text(160, row_y, term, [align: :right] ++ opts)
        |> text(@right, row_y, value, [align: :right] ++ opts)
      end)

    %{s | y: y + length(view.totals) * 5.5}
  end

  defp mentions(%{view: %{mentions: []}} = s), do: s

  defp mentions(%{view: view} = s) do
    rows = Enum.flat_map(view.mentions, &Pdf.wrap(s.pdf, &1, mm(@right - @left), size: 8.5))
    s = ensure(s, 6 + length(rows) * 4, & &1)
    y = s.y + 5

    s =
      rows
      |> Enum.with_index()
      |> Enum.reduce(s, fn {row, index}, s -> text(s, @left, y + index * 4, row, size: 8.5) end)

    %{s | y: y + length(rows) * 4}
  end

  defp authority(%{view: %{authority: nil}} = s), do: s

  defp authority(%{view: %{authority: authority}} = s) do
    qr_size = if authority.qr, do: 26, else: 0

    url_rows =
      if authority.qr_url, do: Pdf.wrap(s.pdf, authority.qr_url, mm(120), size: 6.5), else: []

    rows = length(authority.rows) + if(authority.pending, do: 1, else: 0)
    height = max(qr_size + 4, 9 + rows * 4.4 + length(url_rows) * 3)
    s = ensure(s, height + 6, & &1)
    top = s.y + 5
    s = box(s, @left, top, @right - @left, height, 0.5)
    s = text(s, @left + 3, top + 5, authority.title, font: :bold, size: 9)

    s =
      if authority.pending, do: text(s, @left + 3, top + 9.5, authority.pending, size: 9), else: s

    s =
      authority.rows
      |> Enum.with_index()
      |> Enum.reduce(s, fn {{term, value}, index}, s ->
        text(s, @left + 3, top + 9.5 + index * 4.4, "#{term}: #{value}", size: 9)
      end)

    url_top = top + 9.5 + length(authority.rows) * 4.4

    s =
      url_rows
      |> Enum.with_index()
      |> Enum.reduce(s, fn {row, index}, s ->
        text(s, @left + 3, url_top + index * 3, row, size: 6.5, color: {0.3, 0.3, 0.3})
      end)

    s =
      if authority.qr,
        do: qr(s, @right - 2 - qr_size, top + 2, qr_size, authority.qr, false),
        else: s

    %{s | y: top + height}
  end

  defp bank(%{view: %{bank: nil}} = s), do: s

  defp bank(%{view: %{bank: bank}} = s) do
    s = ensure(s, 8 + length(bank.rows) * 4.4, & &1)
    y = s.y + 6
    s = text(s, @left, y, String.upcase(bank.title), size: 7.5, color: {0.3, 0.3, 0.3})

    s =
      bank.rows
      |> Enum.with_index()
      |> Enum.reduce(s, fn {{term, value}, index}, s ->
        text(s, @left, y + 4.5 + index * 4.4, "#{term}: #{value}", size: 9)
      end)

    %{s | y: y + 4.5 + length(bank.rows) * 4.4}
  end

  defp footer(%{view: view} = s) do
    {label, hash} = view.fingerprint
    rows = view.footer ++ if(hash, do: ["#{label}: #{hash}"], else: [])
    rows = Enum.flat_map(rows, &Pdf.wrap(s.pdf, &1, mm(@right - @left), size: 7))
    s = ensure(s, 6 + length(rows) * 3.4, & &1)
    y = s.y + 6

    s =
      rows
      |> Enum.with_index()
      |> Enum.reduce(s, fn {row, index}, s ->
        text(s, @left, y + index * 3.4, row, size: 7, color: {0.3, 0.3, 0.3})
      end)

    page_number(%{s | y: y + length(rows) * 3.4})
  end

  # ── QR-bill (SIX IG v2.4 §3) ─────────────────────────────────────────────

  defp qr_bill(%{view: %{qr_bill: nil}} = s), do: s

  defp qr_bill(%{view: %{qr_bill: bill}} = s) do
    h = bill.headings
    pdf = Pdf.add_page(s.pdf)
    s = %{s | pdf: pdf, page: s.page + 1, y: 0}
    top = @page_height - 105

    s =
      s
      |> text(105, top - 1.5, h.separate, size: 7, align: :center)
      |> dashed(0, top, 210, top)
      |> dashed(62, top, 62, @page_height)

    # Receipt (62 × 105 mm).
    s = text(s, 5, top + 9, h.receipt, font: :bold, size: 11)

    {s, y} =
      slip_block(s, 5, top + 15, h.account, [bill.account | bill.creditor_lines], 6, 8, 52)

    {s, y} =
      if bill.reference,
        do: slip_block(s, 5, y + 3.5, h.reference, [bill.reference], 6, 8, 52),
        else: {s, y}

    s =
      if bill.debtor_lines do
        {s, _y} = slip_block(s, 5, y + 3.5, h.payable_by, bill.debtor_lines, 6, 8, 52)
        s
      else
        s
        |> text(5, y + 5, h.payable_by_blank, font: :bold, size: 6)
        |> box(5, y + 6.5, 52, 20, 0.75)
      end

    s =
      s
      |> text(5, top + 70, h.currency, font: :bold, size: 6)
      |> text(5, top + 74, bill.currency, size: 8)
      |> text(18, top + 70, h.amount, font: :bold, size: 6)

    s =
      if bill.amount,
        do: text(s, 18, top + 74, bill.amount, size: 8),
        else: box(s, 27, top + 71, 30, 10, 0.75)

    s = text(s, 57, top + 85, h.acceptance_point, font: :bold, size: 6, align: :right)

    # Payment part (148 × 105 mm).
    s = text(s, 67, top + 9, h.payment_part, font: :bold, size: 11)
    s = qr(s, 67, top + 17, 46, bill.qr, true)

    s =
      s
      |> text(67, top + 73, h.currency, font: :bold, size: 8)
      |> text(67, top + 78, bill.currency, size: 10)
      |> text(80, top + 73, h.amount, font: :bold, size: 8)

    s =
      if bill.amount,
        do: text(s, 80, top + 78, bill.amount, size: 10),
        else: box(s, 78, top + 75, 40, 15, 0.75)

    {s, y} =
      slip_block(s, 118, top + 7, h.account, [bill.account | bill.creditor_lines], 8, 10, 87)

    {s, y} =
      if bill.reference,
        do: slip_block(s, 118, y + 4.5, h.reference, [bill.reference], 8, 10, 87),
        else: {s, y}

    {s, y} =
      if bill.message,
        do: slip_block(s, 118, y + 4.5, h.additional_information, [bill.message], 8, 10, 87),
        else: {s, y}

    if bill.debtor_lines do
      {s, _y} = slip_block(s, 118, y + 4.5, h.payable_by, bill.debtor_lines, 8, 10, 87)
      s
    else
      s
      |> text(118, y + 6, h.payable_by_blank, font: :bold, size: 8)
      |> box(118, y + 8, 65, 25, 0.75)
    end
  end

  # A heading and its values; returns the state and the y of the last baseline.
  defp slip_block(s, x, y, heading, values, heading_size, value_size, width) do
    s = text(s, x, y, heading, font: :bold, size: heading_size)
    step = value_size * 0.42

    values
    |> Enum.flat_map(&Pdf.wrap(s.pdf, &1, mm(width), size: value_size))
    |> Enum.reduce({s, y}, fn row, {s, last} ->
      next = last + step
      {text(s, x, next, row, size: value_size), next}
    end)
  end

  # ── Drawing helpers (millimetres from the top-left corner) ───────────────

  defp text(s, x, y, value, opts),
    do: %{s | pdf: Pdf.text(s.pdf, mm(x), mm(@page_height - y), value, opts)}

  defp hline(s, y, width, color \\ nil, to \\ @right) do
    opts = [line_width: width] ++ if(color, do: [color: color], else: [])

    %{
      s
      | pdf: Pdf.line(s.pdf, mm(@left), mm(@page_height - y), mm(to), mm(@page_height - y), opts)
    }
  end

  defp dashed(s, x1, y1, x2, y2),
    do: %{
      s
      | pdf:
          Pdf.line(s.pdf, mm(x1), mm(@page_height - y1), mm(x2), mm(@page_height - y2),
            line_width: 0.5,
            dash: [2, 2]
          )
    }

  defp box(s, x, y, width, height, line_width),
    do: %{
      s
      | pdf:
          Pdf.rect(s.pdf, mm(x), mm(@page_height - y - height), mm(width), mm(height),
            fill: false,
            stroke: true,
            line_width: line_width
          )
    }

  defp fill(s, x, y, width, height, color),
    do: %{
      s
      | pdf:
          Pdf.rect(s.pdf, mm(x), mm(@page_height - y - height), mm(width), mm(height),
            color: color
          )
    }

  # A QR code of `size` mm with its top-left corner at {x, y}; the Swiss
  # cross is 7 × 7 mm in the middle of a 46 mm code.
  defp qr(s, x, y, size, %{size: modules, dark: dark}, cross?) do
    unit = size / modules

    s =
      Enum.reduce(dark, s, fn {column, row}, s ->
        fill(s, x + column * unit, y + row * unit, unit, unit, {0, 0, 0})
      end)

    if cross? do
      c = size / 2

      s
      |> fill(x + c - 3.5, y + c - 3.5, 7, 7, {1, 1, 1})
      |> fill(x + c - 3, y + c - 3, 6, 6, {0, 0, 0})
      |> fill(x + c - 0.6, y + c - 1.95, 1.2, 3.9, {1, 1, 1})
      |> fill(x + c - 1.95, y + c - 0.6, 3.9, 1.2, {1, 1, 1})
    else
      s
    end
  end

  # Starts a new page when `height` mm does not fit; `after_break` redraws
  # what a continued section needs (the table head).
  defp ensure(s, height, after_break) do
    if s.y + height > @page_height - @bottom do
      s = page_number(s)
      s = %{s | pdf: Pdf.add_page(s.pdf), page: s.page + 1, y: 18}
      after_break.(s)
    else
      s
    end
  end

  defp page_number(s),
    do:
      text(s, @right, @page_height - 10, "#{s.view.page_label} #{s.page}", size: 7, align: :right)

  defp mm(value), do: value * @mm
end
