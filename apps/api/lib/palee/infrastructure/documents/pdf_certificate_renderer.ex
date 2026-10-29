defmodule Palee.Infrastructure.Documents.PdfCertificateRenderer do
  @moduledoc """
  The signature certificate as a PDF (ADR-252, port
  `Documents.Ports.CertificateRenderer`): the signed text as it was shown,
  then the evidence of the signature (who, when, from where, with what,
  the drawn strokes and the SHA-256 of the text and of the evidence).
  Labels are bilingual (Greek · English), like the gym's documents.
  """

  @behaviour Palee.Documents.Ports.CertificateRenderer

  alias Palee.Infrastructure.Documents.Pdf.{TrueType, Writer}

  @margin 56
  @body_size 10
  @small_size 8
  @leading 1.38
  @footer_y 32

  @impl true
  def render(certificate) do
    {width, height} = Writer.page_size()
    font = Writer.font()
    text_width = width - 2 * @margin

    blocks =
      header(certificate) ++
        body(certificate.body) ++
        evidence(certificate)

    pages = paginate(font, blocks, text_width, height)
    total = length(pages)

    pages =
      pages
      |> Enum.with_index(1)
      |> Enum.map(fn {operations, number} ->
        operations ++ footer(font, certificate, number, total, width)
      end)

    {:ok,
     Writer.render(pages, %{
       title: certificate.title,
       subject: "Πιστοποιητικό υπογραφής · Signature certificate",
       created_at: certificate.evidence.signed_at,
       id: String.slice(certificate.evidence_hash, 0, 32)
     })}
  rescue
    error -> {:error, {:certificate_render_failed, Exception.message(error)}}
  end

  # ── Blocks ────────────────────────────────────────────────────────────────
  # A block is {:paragraph, text, size, indent, space_before} or
  # {:signature, drawn, label, space_before} or {:rule, space_before}.

  defp header(certificate) do
    [
      {:paragraph, certificate.business_name || "", @small_size, 0, 0},
      {:paragraph, certificate.title, 16, 0, 6},
      {:paragraph,
       "Έκδοση · Version #{certificate.version_number} · #{certificate.language} · " <>
         "SHA-256 #{certificate.evidence.content_hash}", @small_size, 0, 4},
      {:rule, 8}
    ]
  end

  defp body(text) do
    text
    |> String.split("\n")
    |> Enum.map(&line_block/1)
  end

  defp line_block("# " <> heading), do: {:paragraph, clean(heading), 14, 0, 8}
  defp line_block("## " <> heading), do: {:paragraph, clean(heading), 12, 0, 6}
  defp line_block("### " <> heading), do: {:paragraph, clean(heading), 11, 0, 4}
  defp line_block("- " <> item), do: {:paragraph, "• " <> clean(item), @body_size, 12, 0}
  defp line_block("* " <> item), do: {:paragraph, "• " <> clean(item), @body_size, 12, 0}
  defp line_block(""), do: {:paragraph, "", @body_size, 0, 0}
  defp line_block(line), do: {:paragraph, clean(line), @body_size, 0, 0}

  defp clean(text), do: text |> String.replace(~r/(\*\*|__|`)/u, "") |> String.trim_trailing()

  defp evidence(%{evidence: evidence, evidence_hash: evidence_hash} = certificate) do
    signer = evidence.signer

    rows =
      [
        {"Υπογράφων · Signed by", signer_name(signer)},
        {"Λογαριασμός · Account",
         Enum.join(Enum.reject([signer[:user_id], signer[:email]], &is_nil/1), " · ")},
        {"Πληκτρολογημένο όνομα · Typed name", evidence.typed_name},
        {"Ημερομηνία (UTC) · Signed at (UTC)", DateTime.to_iso8601(evidence.signed_at)},
        {"Τοπική ώρα · Local time", certificate[:local_signed_at]},
        {"Διεύθυνση IP · IP address", evidence.ip_address},
        {"Συσκευή · Device", evidence.user_agent},
        {"Έγγραφο · Document",
         "#{evidence.template_id} · v#{evidence.version_number} (#{evidence.version_id})"},
        {"SHA-256 κειμένου · Text SHA-256", evidence.content_hash},
        {"Υπογραφή · Signature", evidence.signature_id},
        {"Είδος · Type",
         "Απλή ηλεκτρονική υπογραφή · Simple electronic signature (eIDAS art. 3(10), 25(1)) · #{evidence.provider}"},
        {"SHA-256 στοιχείων · Evidence SHA-256", evidence_hash}
      ]
      |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)

    [
      {:rule, 14},
      {:paragraph, "Στοιχεία υπογραφής · Evidence of signature", 13, 0, 4}
    ] ++
      Enum.flat_map(rows, fn {label, value} ->
        [
          {:paragraph, label, @small_size, 0, 5},
          {:paragraph, to_string(value), @body_size, 0, 0}
        ]
      end) ++
      drawn(evidence.drawn_signature) ++
      [
        {:paragraph,
         "Το SHA-256 κειμένου ταυτοποιεί το ακριβές κείμενο που υπογράφηκε και το SHA-256 στοιχείων " <>
           "την παραπάνω εγγραφή, όπως φυλάσσεται στο Palee. · The text SHA-256 identifies the exact " <>
           "text signed and the evidence SHA-256 the record above, as kept by Palee.",
         @small_size, 0, 12}
      ]
  end

  defp drawn(nil), do: []

  defp drawn(drawn) do
    [{:signature, drawn, "Ιδιόχειρη υπογραφή · Drawn signature", 5}]
  end

  defp signer_name(signer) do
    case {signer[:display_name], signer[:nickname]} do
      {nil, nil} -> nil
      {name, nil} -> name
      {nil, nickname} -> "@" <> nickname
      {name, nickname} -> "#{name} (@#{nickname})"
    end
  end

  # ── Layout ────────────────────────────────────────────────────────────────

  @signature_height 90

  defp paginate(font, blocks, text_width, height) do
    top = height - @margin
    bottom = @margin + 12

    {pages, current, _y} =
      Enum.reduce(blocks, {[], [], top}, fn block, {pages, current, y} ->
        place(font, block, text_width, {pages, current, y}, top, bottom)
      end)

    Enum.reverse([Enum.reverse(current) | pages])
  end

  defp place(font, {:paragraph, text, size, indent, before}, text_width, state, top, bottom) do
    line_height = size * @leading

    font
    |> wrap(text, size, text_width - indent)
    |> Enum.with_index()
    |> Enum.reduce(state, fn {line, index}, {pages, current, y} ->
      y = if index == 0, do: y - before, else: y
      {pages, current, y} = ensure(pages, current, y, line_height, top, bottom)
      baseline = y - size

      {pages, [{:text, @margin + indent, baseline, size, line} | current], y - line_height}
    end)
  end

  defp place(_font, {:rule, before}, text_width, {pages, current, y}, top, bottom) do
    {pages, current, y} = ensure(pages, current, y - before, 6, top, bottom)

    {pages, [{:polyline, [{@margin, y}, {@margin + text_width, y}], 0.5} | current], y - 6}
  end

  # The label and the drawing always stay on the same page.
  defp place(_font, {:signature, drawn, label, before}, _width, {pages, current, y}, top, bottom) do
    label_height = @small_size * @leading + 4

    {pages, current, y} =
      ensure(pages, current, y - before, label_height + @signature_height, top, bottom)

    current = [{:text, @margin, y - @small_size, @small_size, label} | current]
    y = y - label_height
    box_width = @signature_height * drawn.width / max(drawn.height, 1)
    box_width = min(box_width, 300)
    scale = min(box_width / drawn.width, @signature_height / drawn.height)
    origin_y = y - @signature_height

    strokes =
      Enum.map(drawn.strokes, fn points ->
        points =
          Enum.map(points, fn [px, py] ->
            {@margin + px * scale, origin_y + (drawn.height - py) * scale}
          end)

        points = if length(points) == 1, do: points ++ [nudge(hd(points))], else: points
        {:polyline, points, 1.2}
      end)

    frame = {:rect, @margin, origin_y, drawn.width * scale, drawn.height * scale, 0.3}
    {pages, Enum.reverse([frame | strokes]) ++ current, origin_y - 6}
  end

  defp nudge({x, y}), do: {x + 0.5, y}

  defp ensure(pages, current, y, needed, top, bottom) do
    if y - needed < bottom and current != [],
      do: {[Enum.reverse(current) | pages], [], top},
      else: {pages, current, y}
  end

  defp footer(font, certificate, number, total, width) do
    text =
      "Palee · #{certificate.evidence.signature_id} · #{number}/#{total}"

    size = @small_size
    x = width - @margin - TrueType.text_width(font, text, size)
    [{:text, max(x, @margin), @footer_y, size, text}]
  end

  # Greedy word wrap; words longer than a line are broken by characters.
  defp wrap(_font, "", _size, _width), do: [""]

  defp wrap(font, text, size, width) do
    text
    |> String.split(" ")
    |> Enum.flat_map(&split_long(font, &1, size, width))
    |> Enum.reduce([], fn word, lines ->
      case lines do
        [] ->
          [word]

        [line | rest] ->
          candidate = line <> " " <> word

          if TrueType.text_width(font, candidate, size) <= width,
            do: [candidate | rest],
            else: [word, line | rest]
      end
    end)
    |> Enum.reverse()
  end

  defp split_long(font, word, size, width) do
    if TrueType.text_width(font, word, size) <= width do
      [word]
    else
      word
      |> String.graphemes()
      |> Enum.reduce([""], fn grapheme, [current | rest] ->
        candidate = current <> grapheme

        if TrueType.text_width(font, candidate, size) <= width or current == "",
          do: [candidate | rest],
          else: [grapheme, current | rest]
      end)
      |> Enum.reverse()
    end
  end
end
