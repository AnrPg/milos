defmodule Palee.Infrastructure.Documents.PdfCertificateRendererTest do
  @moduledoc """
  ADR-252: the signature certificate is a well-formed PDF with an embedded
  Unicode font subset (Greek included), a valid cross-reference table, the
  evidence on it, and the same bytes for the same evidence.
  """

  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Documents.Pdf.{TrueType, Writer}
  alias Palee.Infrastructure.Documents.PdfCertificateRenderer

  @evidence %{
    signature_id: "11111111-2222-4333-8444-555555555555",
    template_id: "aaaaaaaa-2222-4333-8444-555555555555",
    version_id: "bbbbbbbb-2222-4333-8444-555555555555",
    version_number: 2,
    content_hash: String.duplicate("ab", 32),
    signed_at: ~U[2027-02-08 10:00:00.123456Z],
    level: "simple",
    provider: "palee",
    signer: %{
      user_id: "cccccccc-2222-4333-8444-555555555555",
      display_name: "Μαρία Παπαδοπούλου",
      nickname: "maria",
      email: "maria@example.com"
    },
    typed_name: "Μαρία Παπαδοπούλου",
    drawn_signature: %{
      width: 300,
      height: 100,
      strokes: [[[10, 50], [50, 20], [90, 80]], [[200, 60]]]
    },
    ip_address: "203.0.113.7",
    user_agent: "Mozilla/5.0 (iPhone)"
  }

  defp certificate(body) do
    %{
      business_name: "CrossFit Κυψέλη",
      local_signed_at: "08/02/2027 12:00:00 (Europe/Athens)",
      title: "Υπεύθυνη δήλωση",
      language: "el",
      body: body,
      version_number: 2,
      evidence: @evidence,
      evidence_hash: String.duplicate("cd", 32)
    }
  end

  defp long_body,
    do:
      "# Υπεύθυνη δήλωση\n\n" <>
        String.duplicate("Ο αθλητής αναλαμβάνει την ευθύνη για την προπόνησή του. ", 120) <>
        "\n\n- **Πρώτο** σημείο\n- Second point\n\n## Τέλος\nÜnïcødé € ✓"

  test "renders a PDF with a valid cross-reference table and pages" do
    assert {:ok, pdf} = PdfCertificateRenderer.render(certificate(long_body()))

    assert "%PDF-1.7" <> _ = pdf
    assert String.ends_with?(pdf, "%%EOF\n")
    assert [_, count] = Regex.run(~r{/Type /Pages /Count (\d+)}, pdf)
    assert String.to_integer(count) >= 2

    [_, startxref] = Regex.run(~r/startxref\n(\d+)\n%%EOF\n$/, pdf)
    startxref = String.to_integer(startxref)
    assert binary_part(pdf, startxref, 4) == "xref"

    [_, size] = Regex.run(~r{/Size (\d+)}, pdf)

    offsets =
      Regex.scan(~r/(\d{10}) 00000 n /, binary_part(pdf, startxref, byte_size(pdf) - startxref))
      |> Enum.map(fn [_, offset] -> String.to_integer(offset) end)

    assert length(offsets) == String.to_integer(size) - 1

    for {offset, id} <- Enum.with_index(offsets, 1) do
      assert binary_part(pdf, offset, byte_size("#{id} 0 obj")) == "#{id} 0 obj"
    end
  end

  test "embeds a small font subset with a ToUnicode map, and the info dictionary" do
    {:ok, pdf} = PdfCertificateRenderer.render(certificate("Σύντομο κείμενο."))

    assert pdf =~ "/Subtype /CIDFontType2"
    assert pdf =~ "/Encoding /Identity-H"
    assert pdf =~ "/ToUnicode 8 0 R"
    assert pdf =~ ~r"/BaseFont /[A-Z]{6}\+DejaVuSans"
    # A subset, not the 750 KB font.
    assert byte_size(pdf) < 60_000
    assert pdf =~ "/CreationDate <FEFF"
    assert pdf =~ "/Producer <FEFF"
  end

  test "the same evidence gives the same bytes" do
    assert PdfCertificateRenderer.render(certificate("Κείμενο")) ==
             PdfCertificateRenderer.render(certificate("Κείμενο"))

    refute PdfCertificateRenderer.render(certificate("Κείμενο")) ==
             PdfCertificateRenderer.render(certificate("Κείμενο."))
  end

  test "the font maps Greek and Latin, and the subset keeps the glyphs it needs" do
    font = Writer.font()
    alpha = TrueType.glyph(font, ?α)
    a = TrueType.glyph(font, ?a)
    accented = TrueType.glyph(font, ?ά)

    assert alpha > 0 and a > 0 and accented > 0
    assert TrueType.glyph(font, 0x10FFFF) == 0
    assert TrueType.text_width(font, "αα", 10) == 2 * TrueType.text_width(font, "α", 10)

    subset = font |> TrueType.subset([alpha, a, accented]) |> TrueType.parse()
    assert subset.num_glyphs == font.num_glyphs
    assert subset.units_per_em == font.units_per_em
    assert subset.index_to_loc_format == 1
    assert byte_size(subset.tables["glyf"]) < byte_size(font.tables["glyf"]) / 20

    glyph_size = fn parsed, glyph ->
      <<_::binary-size(glyph * 4), start::32, stop::32, _::binary>> = parsed.tables["loca"]
      stop - start
    end

    assert glyph_size.(subset, alpha) > 0
    assert glyph_size.(subset, TrueType.glyph(font, ?z)) == 0
  end
end
