defmodule Palee.PdfTest do
  @moduledoc "ADR-245 PDF writer: TrueType parsing and subsetting, text layout and the file."

  use ExUnit.Case, async: true

  alias Palee.Pdf
  alias Palee.Pdf.{Fonts, TrueType}

  test "parses Liberation Sans, measures text and subsets glyphs" do
    %{regular: regular} = fonts = Fonts.sans()
    assert %TrueType{} = regular

    a = TrueType.glyph(regular, ?A)
    alpha = TrueType.glyph(regular, ?α)
    assert a > 0 and alpha > 0
    assert TrueType.glyph(regular, 0x1F600) == 0

    assert TrueType.text_width(regular, "AA", 10) == 2 * TrueType.text_width(regular, "A", 10)

    subset = TrueType.subset(regular, [0, a, alpha])
    assert is_binary(subset)
    assert byte_size(subset) < 60_000
    # A CID font program: glyph ids kept, no cmap (the PDF maps codes itself).
    assert <<0, 1, 0, 0, tables::16, _rest::binary>> = subset
    assert tables >= 6
    assert Map.has_key?(fonts, :bold)
  end

  test "lays out, wraps and renders a deterministic file" do
    pdf =
      Fonts.sans()
      |> Pdf.new()
      |> Pdf.text(20, 20, "Τιμολόγιο Παροχής Υπηρεσιών – Grüße", size: 12, font: :bold)
      |> Pdf.rect(20, 30, 50, 10)
      |> Pdf.line(20, 50, 100, 50, dash: [1, 1])

    lines = Pdf.wrap(pdf, String.duplicate("word ", 40), 60, size: 10)
    assert length(lines) > 1
    assert Enum.all?(lines, &(Pdf.text_width(pdf, &1, size: 10) <= 60 + 0.01))

    # A word longer than a line (a TSE signature) is cut in order, after a short one.
    long = Enum.map_join(1..30, &"#{rem(&1, 10)}")
    [first | rest] = Pdf.wrap(pdf, "Signatur: " <> long, 60, size: 10)
    assert first == "Signatur:"
    assert Enum.join(rest) == long

    pdf = Pdf.add_page(pdf)
    assert Pdf.page_count(pdf) == 2
    assert ["Τιμολόγιο Παροχής Υπηρεσιών – Grüße"] = Pdf.texts(pdf)

    info = [title: "Test", created_at: ~U[2027-02-03 10:00:00Z]]
    file = Pdf.render(pdf, info)
    assert "%PDF-1.7" <> _rest = file
    assert file == Pdf.render(pdf, info)
    assert file =~ "/Count 2"
  end
end
