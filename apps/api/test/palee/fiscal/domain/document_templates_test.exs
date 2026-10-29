defmodule Palee.Fiscal.Domain.DocumentTemplatesTest do
  @moduledoc """
  ADR-245 templates without a database: the Swiss QR-bill (SIX IG v2.4),
  QR codes, the document view per country, its HTML and PDF renderings and
  the translated labels.
  """

  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.{
    DocumentHtml,
    DocumentLabels,
    DocumentPdf,
    DocumentView,
    QrBill,
    QrCode
  }

  alias Palee.Pdf.Fonts

  @creditor %{
    name: "CrossFit Zürich AG",
    street: "Bahnhofstrasse",
    building_number: "10",
    postal_code: "8001",
    city: "Zürich",
    country_code: "CH"
  }

  defp line(position, description, unit, category, rate, net, tax, extra \\ %{}) do
    Map.merge(
      %{
        position: position,
        description: description,
        quantity: 1,
        unit_price_cents: unit,
        discount_cents: 0,
        amount_cents: unit,
        tax_category: category,
        rate_bp: rate,
        exemption_reason: nil,
        net_cents: net,
        tax_cents: tax,
        gross_cents: net + tax,
        source_type: nil
      },
      extra
    )
  end

  defp swiss_invoice(extra \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        kind: "invoice",
        series: "I",
        sequence: 42,
        number: "I-000042",
        issue_date: ~D[2027-02-03],
        currency: "CHF",
        prices_include_tax: true,
        country_code: "CH",
        language: "de",
        payment_method: nil,
        corrects_document_id: nil,
        content_hash: String.duplicate("ab", 32),
        seller: %{
          "legal_name" => "CrossFit Zürich AG",
          "street" => "Bahnhofstrasse",
          "building_number" => "10",
          "postal_code" => "8001",
          "city" => "Zürich",
          "country_code" => "CH",
          "tax_id" => "CHE-109.322.551",
          "vat_scheme" => "standard"
        },
        buyer: %{
          "name" => "Muster Treuhand GmbH",
          "street" => "Seestrasse",
          "building_number" => "5",
          "postal_code" => "8002",
          "city" => "Zürich",
          "country_code" => "CH"
        },
        net_cents: 18_501,
        tax_cents: 1_499,
        gross_cents: 20_000,
        tax_breakdown: [
          %{
            "tax_category" => "standard",
            "rate_bp" => 810,
            "net_cents" => 18_501,
            "tax_cents" => 1_499,
            "gross_cents" => 20_000
          }
        ],
        lines: [line(1, "Unlimited – Februar 2027", 20_000, "standard", 810, 18_501, 1_499)]
      },
      extra
    )
  end

  defp greek_receipt(extra \\ %{}) do
    swiss_invoice(
      Map.merge(
        %{
          kind: "receipt",
          series: "R",
          number: "R-000007",
          currency: "EUR",
          country_code: "GR",
          language: "el",
          payment_method: "card",
          buyer: nil,
          seller: %{
            "legal_name" => "CrossFit Αθήνα ΙΚΕ",
            "street" => "Πανεπιστημίου",
            "building_number" => "10",
            "postal_code" => "10563",
            "city" => "Αθήνα",
            "country_code" => "GR",
            "tax_id" => "090000045",
            "tax_office" => "Α' Αθηνών",
            "vat_scheme" => "standard"
          },
          net_cents: 16_129,
          tax_cents: 3_871,
          tax_breakdown: [
            %{
              "tax_category" => "standard",
              "rate_bp" => 2400,
              "net_cents" => 16_129,
              "tax_cents" => 3_871,
              "gross_cents" => 20_000
            }
          ],
          lines: [line(1, "Μηνιαία συνδρομή", 20_000, "standard", 2400, 16_129, 3_871)]
        },
        extra
      )
    )
  end

  @identity %{iban: "CH5604835012345678009", qr_iban: "CH4431999123000889012"}

  describe "QR references" do
    test "QR reference check digits (mod 10 recursive), as in the SIX examples" do
      assert QrBill.valid_qr_reference?("210000000003139471430009017")
      assert QrBill.valid_qr_reference?("000008207791225857421286694")
      refute QrBill.valid_qr_reference?("210000000003139471430009018")
      assert QrBill.qr_reference("21000000000313947143000901") == "210000000003139471430009017"
    end

    test "creditor references (ISO 11649)" do
      assert QrBill.valid_creditor_reference?("RF18539007547034")
      refute QrBill.valid_creditor_reference?("RF19539007547034")
      assert QrBill.creditor_reference("539007547034") == "RF18539007547034"
    end

    test "amounts print with a space every three digits" do
      assert QrBill.print_amount(159_000) == "1 590.00"
      assert QrBill.print_amount(5) == "0.05"
    end
  end

  describe "QR-bill payload" do
    test "QR-IBAN with a QR reference: 31 lines in the guideline's order" do
      assert {:ok, bill} =
               QrBill.build(%{
                 account: "CH44 3199 9123 0008 8901 2",
                 creditor: @creditor,
                 debtor: %{
                   name: "Pia-Maria Rutschmann-Schnyder",
                   street: "Grosse Marktgasse",
                   building_number: "28",
                   postal_code: "9400",
                   city: "Rorschach",
                   country_code: "CH"
                 },
                 amount_cents: 159_000,
                 currency: "CHF",
                 reference: {:qrr, "21000000000313947143000901"},
                 message: "Invoice I-000042"
               })

      lines = String.split(bill.payload, "\n")
      assert length(lines) == 31
      refute String.ends_with?(bill.payload, "\n")

      assert Enum.slice(lines, 0, 11) == [
               "SPC",
               "0200",
               "1",
               "CH4431999123000889012",
               "S",
               "CrossFit Zürich AG",
               "Bahnhofstrasse",
               "10",
               "8001",
               "Zürich",
               "CH"
             ]

      assert Enum.slice(lines, 11, 7) == List.duplicate("", 7)
      assert Enum.slice(lines, 18, 2) == ["1590.00", "CHF"]
      assert Enum.at(lines, 20) == "S"

      assert Enum.slice(lines, 27, 4) == [
               "QRR",
               "210000000003139471430009017",
               "Invoice I-000042",
               "EPD"
             ]

      assert bill.reference == "21 00000 00003 13947 14300 09017"
      assert bill.account == "CH44 3199 9123 0008 8901 2"
    end

    test "a plain IBAN takes a creditor reference, also in EUR, and no amount is allowed" do
      assert {:ok, bill} =
               QrBill.build(%{
                 account: "CH5604835012345678009",
                 creditor: @creditor,
                 currency: "EUR",
                 reference: {:scor, "539007547034"}
               })

      lines = String.split(bill.payload, "\n")
      assert Enum.slice(lines, 18, 2) == ["", "EUR"]
      assert Enum.slice(lines, 20, 7) == List.duplicate("", 7)
      assert Enum.slice(lines, 27, 2) == ["SCOR", "RF18539007547034"]
    end

    test "rules of the guidelines" do
      base = %{account: "CH5604835012345678009", creditor: @creditor, currency: "CHF"}

      assert {:error, :qr_reference_needs_qr_iban} =
               QrBill.build(Map.put(base, :reference, {:qrr, "1"}))

      assert {:error, :qr_iban_needs_qr_reference} =
               QrBill.build(
                 %{base | account: "CH4431999123000889012"}
                 |> Map.put(:reference, :none)
               )

      assert {:error, :iban_not_swiss} =
               QrBill.build(
                 %{base | account: "DE89370400440532013000"}
                 |> Map.put(:reference, :none)
               )

      assert {:error, :qr_bill_currency} =
               QrBill.build(%{base | currency: "USD"} |> Map.put(:reference, :none))

      assert {:error, :creditor_address_incomplete} =
               QrBill.build(
                 %{base | creditor: Map.delete(@creditor, :city)}
                 |> Map.put(:reference, :none)
               )
    end

    test "a document gets a bill only when it is a Swiss invoice to be paid" do
      assert %{reference_type: "QRR"} =
               QrBill.for_document(swiss_invoice(), @identity, "Rechnung")

      assert %{reference_type: "SCOR"} =
               QrBill.for_document(swiss_invoice(), %{iban: @identity.iban}, "Rechnung")

      assert %{reference_type: "SCOR", currency: "EUR"} =
               QrBill.for_document(swiss_invoice(%{currency: "EUR"}), @identity, "Rechnung")

      assert nil == QrBill.for_document(swiss_invoice(%{payment_method: "card"}), @identity, "x")
      assert nil == QrBill.for_document(swiss_invoice(%{kind: "receipt"}), @identity, "x")
      assert nil == QrBill.for_document(swiss_invoice(), %{}, "x")
    end

    test "text is reduced to the permitted character set" do
      assert QrBill.sanitize("Café “Zürich” – ∑") =~ "Café"
      refute QrBill.sanitize("Café “Zürich” – ∑") =~ "∑"
    end
  end

  test "QR codes: version and error correction fit the payload, quiet zone trimmed" do
    assert {:ok, %{size: size, dark: dark}} = QrCode.modules("SPC\n0200\n1", :m)
    assert size >= 21 and rem(size - 17, 4) == 0
    assert {0, 0} in dark
    assert Enum.all?(dark, fn {x, y} -> x in 0..(size - 1) and y in 0..(size - 1) end)
  end

  describe "document view" do
    test "a Swiss invoice: UID, VAT breakdown, bank details and the QR-bill" do
      view =
        DocumentView.build(swiss_invoice(),
          labels: DocumentLabels.messages(),
          language: "de",
          identity: @identity
        )

      assert view.title == "Invoice"
      assert {"UID", "CHE-109.322.551"} in view.seller.ids

      assert [[rate, "185.01 CHF", "14.99 CHF", "200.00 CHF"]] = view.breakdown
      assert rate =~ "8.1"

      assert %{rows: [{"IBAN", "CH56 0483 5012 3456 7800 9"}]} = view.bank
      assert %{reference_type: "QRR", headings: %{}} = view.qr_bill
      assert view.authority == nil
    end

    test "a Greek receipt: ΑΦΜ/ΔΟΥ, myDATA MARK and QR once reported, pending before" do
      labels = DocumentLabels.messages()

      pending = DocumentView.build(greek_receipt(), labels: labels, language: "el")
      assert pending.title == labels.gr_11_2 or pending.title == labels.gr_11_1
      assert {labels.tax_id_gr, "090000045"} in pending.seller.ids
      assert {labels.tax_office_gr, "Α' Αθηνών"} in pending.seller.ids
      assert pending.authority.pending == labels.mydata_pending

      reported =
        DocumentView.build(greek_receipt(),
          labels: labels,
          language: "el",
          transmission: %{
            mark: "400001234567890",
            uid: "ABCDEF0123",
            authentication_code: "XYZ",
            qr_url: "https://mydataapi.aade.gr/TimologioQR/QRInfo?q=abc"
          }
        )

      assert {labels.mydata_mark, "400001234567890"} in reported.authority.rows
      assert %{size: _size} = reported.authority.qr
      assert reported.authority.pending == nil
    end

    test "small business mention, French mentions and the corrected document" do
      labels = DocumentLabels.messages()

      german =
        swiss_invoice(%{
          country_code: "DE",
          currency: "EUR",
          seller: %{
            "legal_name" => "Box Berlin",
            "country_code" => "DE",
            "tax_id" => "21/815/08150",
            "vat_scheme" => "small_business"
          },
          lines: [
            line(1, "Abo", 5_000, "exempt", 0, 5_000, 0, %{
              exemption_reason: "Gemäß § 19 UStG wird keine Umsatzsteuer berechnet"
            })
          ]
        })

      view = DocumentView.build(german, labels: labels, language: "de")
      assert Enum.any?(view.mentions, &(&1 =~ "§ 19 UStG"))
      assert [%{note: "Exempt: Gemäß § 19 UStG" <> _rest}] = view.lines

      french =
        swiss_invoice(%{
          country_code: "FR",
          currency: "EUR",
          seller: %{
            "legal_name" => "Box Paris SAS",
            "country_code" => "FR",
            "registration_number" => "73282932000074",
            "vat_number" => "FR44732829320",
            "vat_scheme" => "small_business"
          },
          buyer: %{"name" => "ACME SARL", "vat_number" => "FR40303265045", "country_code" => "FR"}
        })

      view = DocumentView.build(french, labels: labels, language: "fr")
      assert {labels.siren, "73282932000074"} in view.seller.ids
      assert "TVA non applicable, art. 293 B du CGI" in view.mentions
      assert labels.fr_operation in view.mentions
      assert labels.fr_late_payment in view.mentions

      original = swiss_invoice()

      credit =
        DocumentView.build(
          swiss_invoice(%{
            kind: "credit_note",
            number: "C-000001",
            corrects_document_id: original.id
          }),
          labels: labels,
          language: "en",
          original: original
        )

      assert credit.title == "Credit note"
      assert {_label, "I-000042 (" <> _date} = List.keyfind(credit.meta, labels.corrects, 0)
      assert credit.qr_bill == nil
    end
  end

  describe "till signature (ADR-251)" do
    defp german_invoice do
      swiss_invoice(%{
        number: "I-000043",
        currency: "EUR",
        country_code: "DE",
        language: "de",
        payment_method: "card",
        tax_breakdown: [
          %{
            "tax_category" => "standard",
            "rate_bp" => 1900,
            "net_cents" => 16_807,
            "tax_cents" => 3_193,
            "gross_cents" => 20_000
          }
        ]
      })
    end

    @tse_signature %{
      device: "tse",
      status: "signed",
      qr_code_data: "V0;PALEE-1;Kassenbeleg-V1;Beleg^200.00_0.00_0.00_0.00_0.00^200.00:Unbar;7;12",
      print: [
        %{label: "TSE-Seriennummer", value: "SANDBOX-TSE-1"},
        %{label: "Transaktionsnummer", value: "7"},
        %{label: "Signaturzähler", value: "12"},
        %{label: "Signatur", value: String.duplicate("MEUCIQDx", 14)}
      ]
    }

    test "an invoice paid at the till prints its TSE block with the QR code" do
      labels = DocumentLabels.messages()

      view =
        DocumentView.build(german_invoice(),
          labels: labels,
          language: "de",
          till_signature: @tse_signature
        )

      assert view.authority == nil
      assert view.till.title == labels.till_tse_title
      assert {"Transaktionsnummer", "7"} in view.till.rows
      assert %{size: _size} = view.till.qr

      html = DocumentHtml.render(view)
      assert html =~ labels.till_tse_title
      assert html =~ "Signaturzähler"

      texts =
        view |> DocumentPdf.texts(Fonts.sans()) |> Enum.map(&text_of/1) |> Enum.join(" ")

      assert texts =~ labels.till_tse_title
      assert texts =~ "Transaktionsnummer: 7"
      # The long signature wraps inside the block instead of running off the page.
      assert texts =~ "Signatur: MEUCIQDx"
    end

    test "an RKSV signature prints its code as a QR code, not as a row; none without one" do
      code = "_R1-AT1_PALEE-1_7_2027-02-03T10:00:00_200,00_0,00_0,00_0,00_0,00_x_y_z_sig"

      view =
        DocumentView.build(german_invoice(),
          labels: DocumentLabels.messages(),
          language: "de",
          till_signature: %{
            device: "rksv",
            status: "signed",
            qr_code_data: code,
            print: [%{label: "Belegnummer", value: "7"}, %{label: "QR", value: code}]
          }
        )

      assert view.till.rows == [{"Belegnummer", "7"}]
      assert %{size: _size} = view.till.qr

      assert DocumentView.build(german_invoice(), labels: DocumentLabels.messages()).till == nil
    end
  end

  describe "renderings" do
    test "HTML is self-contained, escaped, with the QR-bill's Swiss cross" do
      view =
        DocumentView.build(
          swiss_invoice(%{
            lines: [line(1, "<script>x</script>", 20_000, "standard", 810, 18_501, 1_499)]
          }),
          labels: DocumentLabels.messages(),
          language: "de",
          identity: @identity
        )

      html = DocumentHtml.render(view)
      assert html =~ "<!DOCTYPE html>" or html =~ "<!doctype html>"
      assert html =~ "&lt;script&gt;"
      refute html =~ "<script>x"
      assert html =~ "<svg"
      assert html =~ "Zahlteil"
      refute html =~ ~r/<link|src="http/
    end

    test "PDF: a valid file with embedded fonts, Greek text and the QR-bill page" do
      fonts = Fonts.sans()

      greek =
        DocumentView.build(greek_receipt(), labels: DocumentLabels.messages(), language: "el")

      pdf = DocumentPdf.render(greek, fonts, created_at: ~U[2027-02-03 10:00:00Z])
      assert "%PDF-1." <> _rest = pdf
      assert pdf =~ "/FontFile2"
      assert pdf =~ "/ToUnicode"
      assert String.ends_with?(String.trim_trailing(pdf), "%%EOF")

      assert pdf == DocumentPdf.render(greek, fonts, created_at: ~U[2027-02-03 10:00:00Z])

      texts = greek |> DocumentPdf.texts(fonts) |> Enum.map(&text_of/1) |> Enum.join(" ")
      assert texts =~ "CrossFit Αθήνα ΙΚΕ"
      assert texts =~ "090000045"

      swiss =
        DocumentView.build(swiss_invoice(),
          labels: DocumentLabels.messages(),
          language: "de",
          identity: @identity
        )

      swiss_texts = swiss |> DocumentPdf.texts(fonts) |> Enum.map(&text_of/1)
      assert "Zahlteil" in swiss_texts
      assert "Empfangsschein" in swiss_texts
      assert swiss.qr_bill.reference in swiss_texts
      assert QrBill.valid_qr_reference?(String.replace(swiss.qr_bill.reference, " ", ""))
    end
  end

  test "every label has a translation in el, de, fr, it, nl and es" do
    po_dir = Path.join([:code.priv_dir(:palee), "gettext"])

    for language <- ~w(el de fr it nl es) do
      po = File.read!(Path.join([po_dir, language, "LC_MESSAGES", "fiscal_documents.po"]))

      for {_key, message} <- DocumentLabels.messages() do
        assert po =~ ~s(msgid "#{escape_po(message)}"), "#{language}: #{message}"
      end

      refute po =~ ~r/msgstr ""\n\n/, "#{language} has an empty translation"
    end
  end

  defp escape_po(text), do: String.replace(text, "\"", "\\\"")

  defp text_of(%{text: text}), do: text
  defp text_of({_x, _y, text}), do: text
  defp text_of(text) when is_binary(text), do: text
end
