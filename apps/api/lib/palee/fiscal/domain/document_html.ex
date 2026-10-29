defmodule Palee.Fiscal.Domain.DocumentHtml do
  @moduledoc """
  A fiscal document as a self-contained, printable A4 HTML page (ADR-245):
  inline styles, no scripts, no external resources, every value
  HTML-escaped. QR codes (myDATA link, Swiss QR-bill) are inline SVG
  drawn from `QrCode` modules. The QR-bill sits at the bottom of its own
  page, 210 × 105 mm (receipt 62 mm, payment part 148 mm), with the
  separation lines and the "separate before paying in" note of a PDF bill.

  Renders a `DocumentView` map; the same view always renders the same bytes.
  """

  alias Palee.Fiscal.Domain.DocumentView

  @doc "The HTML page of `view` (from `DocumentView.build/2`)."
  def render(view) do
    IO.iodata_to_binary([
      "<!DOCTYPE html>\n<html lang=\"",
      e(view.language),
      "\">\n<head>\n<meta charset=\"utf-8\">\n",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>",
      e(view.title),
      " ",
      e(view.number),
      "</title>\n<style>",
      stylesheet(),
      "</style>\n</head>\n<body>\n<main class=\"document\">\n",
      header(view),
      parties(view),
      lines(view),
      breakdown(view),
      totals(view),
      mentions(view),
      authority(view.authority),
      bank(view.bank),
      footer(view),
      "</main>\n",
      qr_bill(view.qr_bill),
      "</body>\n</html>\n"
    ])
  end

  defp header(view) do
    [
      "<header>\n<h1>",
      e(view.title),
      "</h1>\n<dl class=\"meta\">\n",
      Enum.map(view.meta, fn {term, value} -> ["<dt>", e(term), "</dt><dd>", e(value), "</dd>\n"] end),
      "</dl>\n</header>\n"
    ]
  end

  defp parties(view) do
    [
      "<section class=\"parties\">\n",
      party(view.seller_heading, view.seller),
      if(view.buyer, do: party(view.buyer_heading, view.buyer), else: []),
      "</section>\n"
    ]
  end

  defp party(heading, party) do
    [
      "<div class=\"party\">\n<h2>",
      e(heading),
      "</h2>\n<p class=\"name\">",
      e(party.name),
      "</p>\n",
      Enum.map(party.lines, &["<p>", e(&1), "</p>\n"]),
      Enum.map(party.ids, fn {term, value} -> ["<p>", e(term), ": ", e(value), "</p>\n"] end),
      Enum.map(party.contact, &["<p>", e(&1), "</p>\n"]),
      "</div>\n"
    ]
  end

  defp lines(view) do
    c = view.columns
    discount? = view.show_discount

    [
      "<table class=\"lines\">\n<thead><tr><th>",
      e(c.description),
      "</th><th class=\"num\">",
      e(c.quantity),
      "</th><th class=\"num\">",
      e(c.unit_price),
      "</th>",
      if(discount?, do: ["<th class=\"num\">", e(c.discount), "</th>"], else: []),
      "<th class=\"num\">",
      e(c.rate),
      "</th><th class=\"num\">",
      e(c.amount),
      "</th></tr></thead>\n<tbody>\n",
      Enum.map(view.lines, fn line ->
        [
          "<tr><td>",
          e(line.description),
          if(line.note, do: ["<br><small>", e(line.note), "</small>"], else: []),
          "</td><td class=\"num\">",
          e(line.quantity),
          "</td><td class=\"num\">",
          e(line.unit_price),
          "</td>",
          if(discount?, do: ["<td class=\"num\">", e(line.discount), "</td>"], else: []),
          "<td class=\"num\">",
          e(line.rate),
          "</td><td class=\"num\">",
          e(line.amount),
          "</td></tr>\n"
        ]
      end),
      "</tbody>\n</table>\n"
    ]
  end

  defp breakdown(view) do
    [
      "<section class=\"breakdown\">\n<h2>",
      e(view.breakdown_heading),
      "</h2>\n<table>\n<thead><tr>",
      view.breakdown_columns
      |> Enum.with_index()
      |> Enum.map(fn {column, index} ->
        ["<th", if(index > 0, do: " class=\"num\"", else: ""), ">", e(column), "</th>"]
      end),
      "</tr></thead>\n<tbody>\n",
      Enum.map(view.breakdown, fn [rate | amounts] ->
        [
          "<tr><td>",
          e(rate),
          "</td>",
          Enum.map(amounts, &["<td class=\"num\">", e(&1), "</td>"]),
          "</tr>\n"
        ]
      end),
      "</tbody>\n</table>\n</section>\n"
    ]
  end

  defp totals(view) do
    [
      "<dl class=\"totals\">\n",
      Enum.map(view.totals, fn {term, value, strong?} ->
        class = if strong?, do: " class=\"grand\"", else: ""
        ["<dt", class, ">", e(term), "</dt><dd", class, ">", e(value), "</dd>\n"]
      end),
      "</dl>\n"
    ]
  end

  defp mentions(%{mentions: []}), do: []

  defp mentions(view),
    do: ["<section class=\"mentions\">\n", Enum.map(view.mentions, &["<p>", e(&1), "</p>\n"]), "</section>\n"]

  defp authority(nil), do: []

  defp authority(authority) do
    [
      "<section class=\"authority\">\n<div>\n<h2>",
      e(authority.title),
      "</h2>\n",
      if(authority.pending, do: ["<p>", e(authority.pending), "</p>\n"], else: []),
      Enum.map(authority.rows, fn {term, value} ->
        ["<p>", e(term), ": <strong>", e(value), "</strong></p>\n"]
      end),
      if(authority.qr_url, do: ["<p class=\"url\">", e(authority.qr_url), "</p>\n"], else: []),
      "</div>\n",
      if(authority.qr, do: ["<div class=\"qr\">", qr_svg(authority.qr, "28mm", nil), "</div>\n"], else: []),
      "</section>\n"
    ]
  end

  defp bank(nil), do: []

  defp bank(bank) do
    [
      "<section class=\"bank\">\n<h2>",
      e(bank.title),
      "</h2>\n",
      Enum.map(bank.rows, fn {term, value} -> ["<p>", e(term), ": ", e(value), "</p>\n"] end),
      "</section>\n"
    ]
  end

  defp footer(view) do
    {fingerprint_label, hash} = view.fingerprint

    [
      "<footer>\n",
      Enum.map(view.footer, &["<p>", e(&1), "</p>\n"]),
      if(hash,
        do: ["<p>", e(fingerprint_label), ": <code>", e(hash), "</code></p>\n"],
        else: []
      ),
      "</footer>\n"
    ]
  end

  # ── QR-bill ───────────────────────────────────────────────────────────────

  defp qr_bill(nil), do: []

  defp qr_bill(bill) do
    h = bill.headings

    [
      "<section class=\"qr-bill\">\n<p class=\"separate\">✂ ",
      e(h.separate),
      "</p>\n<div class=\"slip\">\n<div class=\"receipt\">\n<h3>",
      e(h.receipt),
      "</h3>\n",
      slip_block(h.account, [bill.account | bill.creditor_lines], "r"),
      slip_block(h.reference, List.wrap(bill.reference), "r"),
      debtor_block(bill, h, "r"),
      amount_block(bill, h, "r"),
      "<p class=\"acceptance\">",
      e(h.acceptance_point),
      "</p>\n</div>\n<div class=\"payment\">\n<h3>",
      e(h.payment_part),
      "</h3>\n<div class=\"code\">",
      qr_svg(bill.qr, "46mm", :swiss_cross),
      "</div>\n",
      amount_block(bill, h, "p"),
      "<div class=\"info\">\n",
      slip_block(h.account, [bill.account | bill.creditor_lines], "p"),
      slip_block(h.reference, List.wrap(bill.reference), "p"),
      slip_block(h.additional_information, List.wrap(bill.message), "p"),
      debtor_block(bill, h, "p"),
      "</div>\n</div>\n</div>\n</section>\n"
    ]
  end

  defp slip_block(_heading, [], _part), do: []

  defp slip_block(heading, values, part) do
    [
      "<div class=\"block ",
      part,
      "\"><h4>",
      e(heading),
      "</h4>",
      Enum.map(values, &["<p>", e(&1), "</p>"]),
      "</div>\n"
    ]
  end

  defp debtor_block(%{debtor_lines: nil}, h, part),
    do: [
      "<div class=\"block ",
      part,
      "\"><h4>",
      e(h.payable_by_blank),
      "</h4><div class=\"blank debtor-",
      part,
      "\"></div></div>\n"
    ]

  defp debtor_block(bill, h, part), do: slip_block(h.payable_by, bill.debtor_lines, part)

  defp amount_block(bill, h, part) do
    [
      "<div class=\"amount ",
      part,
      "\"><div><h4>",
      e(h.currency),
      "</h4><p>",
      e(bill.currency),
      "</p></div><div><h4>",
      e(h.amount),
      "</h4>",
      if(bill.amount,
        do: ["<p>", e(bill.amount), "</p>"],
        else: ["<div class=\"blank amount-", part, "\"></div>"]
      ),
      "</div></div>\n"
    ]
  end

  @doc false
  def qr_svg(%{size: size, dark: dark}, width, overlay) do
    path = Enum.map(dark, fn {x, y} -> ["M", Integer.to_string(x), " ", Integer.to_string(y), "h1v1h-1z"] end)

    [
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ",
      Integer.to_string(size),
      " ",
      Integer.to_string(size),
      "\" width=\"",
      width,
      "\" height=\"",
      width,
      "\" shape-rendering=\"crispEdges\"><rect width=\"100%\" height=\"100%\" fill=\"#fff\"/>",
      "<path fill=\"#000\" d=\"",
      path,
      "\"/>",
      if(overlay == :swiss_cross, do: swiss_cross(size), else: []),
      "</svg>"
    ]
  end

  # The 7 × 7 mm Swiss cross on a 46 mm code (SIX IG §6.4.2).
  defp swiss_cross(size) do
    unit = size / 46
    {outer, inner, arm, bar} = {7 * unit, 6 * unit, 3.9 * unit, 1.2 * unit}
    c = size / 2

    [
      rect(c - outer / 2, c - outer / 2, outer, outer, "#fff"),
      rect(c - inner / 2, c - inner / 2, inner, inner, "#000"),
      rect(c - bar / 2, c - arm / 2, bar, arm, "#fff"),
      rect(c - arm / 2, c - bar / 2, arm, bar, "#fff")
    ]
  end

  defp rect(x, y, w, h, fill),
    do: ["<rect x=\"", n(x), "\" y=\"", n(y), "\" width=\"", n(w), "\" height=\"", n(h), "\" fill=\"", fill, "\"/>"]

  defp n(value), do: :erlang.float_to_binary(value * 1.0, [:compact, decimals: 3])

  defp stylesheet do
    "@page{size:A4;margin:0}body{margin:0;background:#f4f4f4;color:#000;" <>
      "font:10pt/1.4 \"Liberation Sans\",Arial,Helvetica,sans-serif}" <>
      ".document{box-sizing:border-box;width:210mm;min-height:297mm;margin:0 auto;padding:18mm 18mm 12mm;" <>
      "background:#fff}header{display:flex;justify-content:space-between;align-items:flex-start;" <>
      "border-bottom:1.5pt solid #000;padding-bottom:4mm}h1{font-size:17pt;margin:0}" <>
      "h2{font-size:8pt;text-transform:uppercase;letter-spacing:.06em;margin:0 0 1.5mm;color:#444}" <>
      "dl.meta{display:grid;grid-template-columns:auto auto;gap:.5mm 4mm;margin:0;font-size:9pt}" <>
      "dl.meta dt{color:#444}dl.meta dd{margin:0;font-weight:700;text-align:right}" <>
      ".parties{display:flex;gap:10mm;margin:6mm 0}.party{flex:1}.party p{margin:0}" <>
      ".party .name{font-weight:700}table{width:100%;border-collapse:collapse}" <>
      "th{font-size:8pt;text-align:left;border-bottom:.75pt solid #000;padding:1mm}" <>
      "td{padding:1mm;border-bottom:.25pt solid #bbb;vertical-align:top}.num{text-align:right;" <>
      "white-space:nowrap}small{color:#444}.breakdown{margin-top:6mm;width:60%}" <>
      "dl.totals{display:grid;grid-template-columns:1fr auto;gap:1mm 6mm;width:45%;margin:4mm 0 0 auto}" <>
      "dl.totals dd{margin:0;text-align:right}.grand{font-weight:700;font-size:12pt}" <>
      ".mentions,.bank,.authority{margin-top:6mm;font-size:9pt}.mentions p,.bank p,.authority p{margin:0}" <>
      ".authority{display:flex;justify-content:space-between;gap:6mm;border:.5pt solid #000;padding:3mm}" <>
      ".authority .url{font-size:7pt;overflow-wrap:anywhere}footer{margin-top:8mm;font-size:7.5pt;" <>
      "color:#444}footer p{margin:0}code{font-size:7pt;overflow-wrap:anywhere}" <>
      ".qr-bill{box-sizing:border-box;width:210mm;height:297mm;margin:0 auto;position:relative;" <>
      "background:#fff;page-break-before:always;break-before:page}.separate{position:absolute;" <>
      "bottom:106mm;left:0;right:0;text-align:center;font-size:8pt;margin:0}.slip{position:absolute;" <>
      "bottom:0;left:0;width:210mm;height:105mm;border-top:.5pt dashed #000;display:flex}" <>
      ".receipt{box-sizing:border-box;width:62mm;padding:5mm;border-right:.5pt dashed #000;" <>
      "position:relative}.payment{box-sizing:border-box;width:148mm;padding:5mm;position:relative}" <>
      "h3{font-size:11pt;margin:0 0 3mm}h4{margin:0;font-size:8pt}.block p{margin:0;font-size:10pt}" <>
      ".block{margin-bottom:3mm}.block.r h4{font-size:6pt}.block.r p{font-size:8pt}" <>
      ".payment .code{position:absolute;left:5mm;top:17mm;width:46mm;height:46mm}" <>
      ".payment .info{position:absolute;left:56mm;top:5mm;width:87mm}" <>
      ".amount{display:flex;gap:5mm}.amount p{margin:0}.amount.p{position:absolute;left:5mm;top:68mm}" <>
      ".amount.r{position:absolute;left:5mm;top:63mm}.amount.r h4{font-size:6pt}.amount.r p{font-size:8pt}" <>
      ".acceptance{position:absolute;right:5mm;top:82mm;margin:0;font-size:6pt;font-weight:700}" <>
      ".blank{border:.75pt solid #000}.debtor-p{width:65mm;height:25mm}.debtor-r{width:52mm;height:20mm}" <>
      ".amount-p{width:40mm;height:15mm}.amount-r{width:30mm;height:10mm}" <>
      "@media print{body{background:#fff}.document{margin:0}}"
  end

  defp e(value), do: DocumentView.escape(value)
end
