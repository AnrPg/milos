defmodule Palee.Fiscal.Domain.AccountingExportFormatsTest do
  @moduledoc """
  ADR-245 accounting exports without a database: the neutral entries, CSV
  writing and every format adapter's file layout.
  """

  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.{ExportCsv, ExportEntries, ExportOptions}

  alias Palee.Infrastructure.Fiscal.Exports.{
    Bexio,
    Datev,
    GenericCsv,
    GenericJson,
    QuickBooks,
    Sage,
    Xero
  }

  @invoice_id "11111111-1111-1111-1111-111111111111"

  defp documents do
    [
      %{
        id: @invoice_id,
        kind: "invoice",
        number: "I-000001",
        issue_date: ~D[2027-02-03],
        currency: "EUR",
        country_code: "DE",
        prices_include_tax: true,
        payment_method: nil,
        corrects_document_id: nil,
        buyer: %{"name" => "Muster GmbH", "vat_number" => "DE136695976", "country_code" => "DE"},
        net_cents: 10_438,
        tax_cents: 1_562,
        gross_cents: 12_000,
        tax_breakdown: [
          %{
            "tax_category" => "standard",
            "rate_bp" => 1900,
            "net_cents" => 8_403,
            "tax_cents" => 1_597,
            "gross_cents" => 10_000
          },
          %{
            "tax_category" => "reduced",
            "rate_bp" => 700,
            "net_cents" => 1_869,
            "tax_cents" => 131,
            "gross_cents" => 2_000
          }
        ]
      },
      %{
        id: "22222222-2222-2222-2222-222222222222",
        kind: "credit_note",
        number: "C-000001",
        issue_date: ~D[2027-02-04],
        currency: "EUR",
        country_code: "DE",
        prices_include_tax: true,
        payment_method: "cash",
        corrects_document_id: @invoice_id,
        buyer: nil,
        net_cents: 1_869,
        tax_cents: 131,
        gross_cents: 2_000,
        tax_breakdown: [
          %{
            "tax_category" => "reduced",
            "rate_bp" => 700,
            "net_cents" => 1_869,
            "tax_cents" => 131,
            "gross_cents" => 2_000
          }
        ]
      }
    ]
  end

  defp lines do
    %{
      @invoice_id => [
        %{
          position: 1,
          description: "Unlimited – Februar",
          quantity: 2,
          unit_price_cents: 5_000,
          discount_cents: 0,
          amount_cents: 10_000,
          tax_category: "standard",
          rate_bp: 1900,
          exemption_reason: nil,
          net_cents: 8_403,
          tax_cents: 1_597,
          gross_cents: 10_000
        },
        %{
          position: 2,
          description: "=Shake",
          quantity: 3,
          unit_price_cents: 700,
          discount_cents: 100,
          amount_cents: 2_000,
          tax_category: "reduced",
          rate_bp: 700,
          exemption_reason: nil,
          net_cents: 1_869,
          tax_cents: 131,
          gross_cents: 2_000
        }
      ],
      "22222222-2222-2222-2222-222222222222" => [
        %{
          position: 1,
          description: "=Shake",
          quantity: 1,
          unit_price_cents: 2_000,
          discount_cents: 0,
          amount_cents: 2_000,
          tax_category: "reduced",
          rate_bp: 700,
          exemption_reason: nil,
          net_cents: 1_869,
          tax_cents: 131,
          gross_cents: 2_000
        }
      ]
    }
  end

  defp payments do
    [
      %{
        "payment_id" => "33333333-3333-3333-3333-333333333333",
        "paid_on" => ~D[2027-02-05],
        "invoice_number" => "INV-7",
        "payment_method" => "bank_transfer",
        "currency" => "EUR",
        "amount_cents" => 12_000,
        "reversed_cents" => 0,
        "net_amount_cents" => 12_000
      },
      %{
        "payment_id" => "44444444-4444-4444-4444-444444444444",
        "paid_on" => ~D[2027-02-05],
        "invoice_number" => nil,
        "payment_method" => "cash",
        "currency" => "EUR",
        "amount_cents" => 500,
        "reversed_cents" => 500,
        "net_amount_cents" => 0
      }
    ]
  end

  defp context(seller \\ %{}) do
    %{
      entries: ExportEntries.build(documents(), lines(), payments()),
      from: ~D[2027-02-01],
      to: ~D[2027-02-28],
      generated_at: ~U[2027-03-01 08:30:15.123456Z],
      seller:
        Map.merge(
          %{legal_name: "Box Berlin GmbH", country_code: "DE", currency: "EUR", vat_scheme: "standard"},
          seller
        )
    }
  end

  defp render(module, options \\ %{}, seller \\ %{}) do
    {:ok, options} = module.normalize_options(options)
    {:ok, result} = module.render(context(seller), options)
    result
  end

  defp csv_rows(content, separator \\ ",") do
    content
    |> String.split("\r\n", trim: true)
    |> Enum.map(&String.split(&1, separator))
  end

  describe "entries" do
    test "credit notes are negative, payments net of reversals, corrected numbers resolved" do
      %{documents: [invoice, credit], payments: [payment]} = context().entries

      assert invoice.sign == 1 and invoice.gross_cents == 12_000
      assert [%{rate_bp: 1900, gross_cents: 10_000}, %{rate_bp: 700}] = invoice.groups
      assert invoice.buyer == %{name: "Muster GmbH", vat_number: "DE136695976", country_code: "DE"}

      assert credit.sign == -1
      assert credit.gross_cents == -2_000
      assert [%{tax_category: "reduced", net_cents: -1_869, tax_cents: -131}] = credit.groups
      assert [%{amount_cents: -2_000, unit_price_cents: 2_000}] = credit.lines
      assert credit.corrects_number == "I-000001"

      assert payment == %{
               id: "33333333-3333-3333-3333-333333333333",
               paid_on: ~D[2027-02-05],
               invoice_number: "INV-7",
               payment_method: "bank_transfer",
               currency: "EUR",
               amount_cents: 12_000,
               reference: "INV-7"
             }
    end

    test "a corrected document outside the period is named by the numbers map" do
      [_invoice, credit] = documents()

      %{documents: [entry]} =
        ExportEntries.build([credit], %{}, [], %{@invoice_id => "I-000000"})

      assert entry.corrects_number == "I-000000"
    end

    test "percentages" do
      assert ExportEntries.percent(1900) == "19"
      assert ExportEntries.percent(550) == "5.5"
      assert ExportEntries.percent(810) == "8.1"
      assert ExportEntries.percent(1225) == "12.25"
    end
  end

  describe "CSV writing" do
    test "quotes, guards formulas and keeps negative numbers" do
      assert ExportCsv.encode([["a,b", "say \"hi\"", "=1+1", "-12.50", "-x", nil, 3]]) ==
               ~s("a,b","say ""hi""",'=1+1,-12.50,'-x,,3\r\n)

      assert ExportCsv.encode([["a;b", "c"]], separator: ";") == ~s("a;b";c\r\n)
    end

    test "amounts, dates and Windows-1252" do
      assert ExportCsv.amount(-123_456, ",") == "-1234,56"
      assert ExportCsv.amount(5) == "0.05"
      assert ExportCsv.date(~D[2027-02-03], :ddmm) == "0302"
      assert ExportCsv.date(~D[2027-02-03], :mdy) == "02/03/2027"
      assert ExportCsv.date(~D[2027-02-03], :dmy_dot) == "03.02.2027"
      assert ExportCsv.to_cp1252("Grüße €–ő Ω") == <<"Gr", 0xFC, 0xDF, "e ", 0x80, 0x96, "o ?">>
    end

    test "options are validated against the format's list" do
      specs = [
        %{key: "n", type: "integer", range: {1, 9}, default: 1},
        %{key: "e", type: "enum", values: ["a", "b"], default: "a"},
        %{key: "m", type: "map", keys: ["standard"], default: %{}}
      ]

      assert {:ok, %{"n" => 5, "e" => "a", "m" => %{"standard" => "8400"}}} =
               ExportOptions.normalize(specs, %{n: "5", m: %{"standard" => 8400}, other: 1})

      assert {:error, {:invalid_fields, errors}} =
               ExportOptions.normalize(specs, %{"n" => 10, "e" => "c", "m" => %{"x" => "1"}})

      assert errors == %{"options.n" => :out_of_range, "options.e" => :invalid, "options.m" => :invalid}
    end
  end

  describe "DATEV" do
    test "EXTF header, 120 columns, one booking per document and rate, Windows-1252" do
      %{content: content, skipped: 0} =
        render(Datev, %{"consultant_number" => 29_098, "client_number" => 55_003})

      assert String.valid?(content) == false or not String.contains?(content, "Ü")
      [header, columns | bookings] = String.split(content, "\r\n", trim: true)

      assert String.split(header, ";") |> Enum.take(17) == [
               ~s("EXTF"),
               "700",
               "21",
               ~s("Buchungsstapel"),
               "9",
               "20270301083015123",
               "",
               ~s("RE"),
               ~s("Palee"),
               ~s(""),
               "29098",
               "55003",
               "20270101",
               "4",
               "20270201",
               "20270228",
               ~s("Palee 2027-02-01-2027-02-28")
             ]

      assert header |> String.split(";") |> length() == 31
      assert header |> String.split(";") |> Enum.at(26) == ~s("03")
      assert columns |> String.split(";") |> length() == 120
      assert length(Datev.columns()) == 120

      assert [standard, reduced, credit] = Enum.map(bookings, &String.split(&1, ";"))
      assert Enum.all?([standard, reduced, credit], &(length(&1) == 120))

      assert Enum.take(standard, 11) ==
               ["100,00", ~s("S"), ~s("EUR"), "", "", "", "1400", "8400", "", "0302", ~s("I-000001")]

      assert Enum.slice(reduced, 0, 2) == ["20,00", ~s("S")]
      assert Enum.at(reduced, 7) == "8300"

      # The credit note was paid back in cash: Haben on the cash account.
      assert Enum.slice(credit, 0, 2) == ["20,00", ~s("H")]
      assert Enum.slice(credit, 6, 2) == ["1000", "8300"]
      assert Enum.at(credit, 11) == ~s("I-000001")
      assert Enum.at(credit, 13) == ~s("Gutschrift C-000001")
    end

    test "SKR04, Kleinunternehmer account, overrides and payments" do
      context = %{context() | entries: %{context().entries | documents: []}}

      {:ok, options} =
        Datev.normalize_options(%{
          "chart" => "SKR04",
          "consultant_number" => 1001,
          "client_number" => 1,
          "include_payments" => true
        })

      {:ok, %{content: content}} = Datev.render(context, options)
      [_header, _columns, payment] = String.split(content, "\r\n", trim: true)
      assert payment |> String.split(";") |> Enum.slice(0, 8) == ["120,00", ~s("S"), ~s("EUR"), "", "", "", "1800", "1200"]

      exempt = [
        %{
          hd(documents())
          | tax_breakdown: [
              %{"tax_category" => "exempt", "rate_bp" => 0, "net_cents" => 100, "tax_cents" => 0, "gross_cents" => 100}
            ]
        }
      ]

      small = %{
        context(%{vat_scheme: "small_business"})
        | entries: ExportEntries.build(exempt, %{}, [])
      }

      {:ok, %{content: content}} = Datev.render(small, options)
      [_header, _columns, booking] = String.split(content, "\r\n", trim: true)
      assert booking |> String.split(";") |> Enum.at(7) == "4185"

      {:ok, options} =
        Datev.normalize_options(%{
          "consultant_number" => 1001,
          "client_number" => 1,
          "revenue_accounts" => %{"exempt" => "8105", "small_business" => "8195"},
          "receivable_account" => "10000"
        })

      {:ok, %{content: content}} = Datev.render(%{small | seller: %{}}, options)
      [_header, _columns, booking] = String.split(content, "\r\n", trim: true)
      assert booking |> String.split(";") |> Enum.slice(6, 2) == ["10000", "8105"]
    end

    test "consultant and client numbers are required" do
      {:ok, options} = Datev.normalize_options(%{})

      assert {:error, {:invalid_fields, %{"options.consultant_number" => :required, "options.client_number" => :required}}} =
               Datev.render(context(), options)

      assert {:error, {:invalid_fields, %{"options.chart" => :invalid}}} =
               Datev.normalize_options(%{"chart" => "SKR99"})
    end
  end

  test "Xero: the 27 template columns, one row per line, credit notes negative" do
    %{content: content, skipped: 1} = render(Xero)
    [header | rows] = csv_rows(content)

    assert header == Xero.columns()
    assert length(header) == 27
    assert Enum.at(header, 0) == "*ContactName"

    assert [first, discounted, credit] = rows

    assert Enum.at(first, 0) == "Muster GmbH"
    assert Enum.slice(first, 10, 4) == ["I-000001", "", "03/02/2027", "03/02/2027"]
    assert Enum.slice(first, 15, 6) == ["Unlimited – Februar", "2", "50.00", "", "200", "19% (VAT on Income)"]
    # A discounted line goes as one unit at its amount; formula text is guarded.
    assert Enum.slice(discounted, 15, 3) == ["'=Shake", "1", "20.00"]
    assert Enum.at(credit, 0) == "Cash sales"
    assert Enum.slice(credit, 10, 2) == ["C-000001", "I-000001"]
    assert Enum.slice(credit, 16, 2) == ["1", "-20.00"]
    assert Enum.at(credit, 25) == "EUR"
  end

  test "QuickBooks Online: invoices only, net amounts with their tax" do
    %{content: content, skipped: skipped} =
      render(QuickBooks, %{"tax_codes" => %{"reduced" => "R7"}})

    # One credit note and one payment cannot be imported.
    assert skipped == 2
    [header | rows] = csv_rows(content)
    assert header == QuickBooks.columns()
    assert [first, second] = rows

    assert first == [
             "I-000001",
             "Muster GmbH",
             "02/03/2027",
             "02/03/2027",
             "Due on receipt",
             "",
             "",
             "Sales",
             "Unlimited – Februar",
             "2",
             "42.015",
             "84.03",
             "19%",
             "15.97",
             "EUR",
             "02/03/2027"
           ]

    assert Enum.slice(second, 9, 5) == ["3", "6.23", "18.69", "R7", "1.31"]
  end

  test "QuickBooks unit rates keep up to four decimals" do
    assert QuickBooks.rate(1000, 3) == "3.3333"
    assert QuickBooks.rate(1000, 4) == "2.50"
    assert QuickBooks.rate(1999, 1) == "19.99"
  end

  test "Sage: SI and SC per rate with T codes, payments as SA" do
    %{content: content, skipped: 0} =
      render(Sage, %{"include_payments" => true, "customer_account" => "GYM01"})

    [header | rows] = csv_rows(content)
    assert header == Sage.columns()

    assert [si_standard, si_reduced, sc, sa] = rows
    assert si_standard == ["SI", "GYM01", "4000", "0", "03/02/2027", "I-000001", "Muster GmbH", "84.03", "T1", "15.97", "", "", "", "", ""]
    assert Enum.slice(si_reduced, 7, 3) == ["18.69", "T5", "1.31"]
    assert Enum.slice(sc, 0, 1) ++ Enum.slice(sc, 7, 4) == ["SC", "18.69", "T5", "1.31", ""]
    assert Enum.at(sc, 11) == "I-000001"
    assert Enum.slice(sa, 0, 3) ++ Enum.slice(sa, 7, 3) == ["SA", "GYM01", "1200", "120.00", "T9", "0.00"]
  end

  test "bexio: gross bookings with the VAT code, credit notes swap accounts" do
    %{content: content, skipped: 1} = render(Bexio)
    [header | rows] = csv_rows(content, ";")
    assert header == ~w(Datum Belegnummer Buchungstext SollKonto HabenKonto Betrag MWST Währung)

    assert [standard, reduced, credit] = rows
    assert standard == ["03.02.2027", "I-000001", "Rechnung I-000001 Muster GmbH", "1100", "3400", "100.00", "UN19", "EUR"]
    assert Enum.slice(reduced, 5, 2) == ["20.00", "UN7"]
    assert Enum.slice(credit, 3, 3) == ["3400", "1000", "20.00"]
  end

  test "generic CSV: one row per line and per payment, signed" do
    %{content: content} = render(GenericCsv, %{"separator" => ";", "amounts" => "decimal_comma"})
    [header | rows] = csv_rows(content, ";")
    assert header == GenericCsv.columns()
    assert length(rows) == 4

    credit = Enum.at(rows, 2)
    assert Enum.slice(credit, 0, 4) == ["line", "22222222-2222-2222-2222-222222222222", "C-000001", "credit_note"]
    assert Enum.slice(credit, -3, 3) == ["-18,69", "-1,31", "-20,00"]

    payment = Enum.at(rows, 3)
    assert Enum.slice(payment, 0, 5) == ["payment", "33333333-3333-3333-3333-333333333333", "INV-7", "payment", "2027-02-05"]
    assert List.last(payment) == "120,00"

    %{content: cents} = render(GenericCsv)
    assert cents =~ ",-2000\r\n"
  end

  test "generic JSON: the entries as they are" do
    %{content: content} = render(GenericJson)
    json = Jason.decode!(content)

    assert json["format"] == "palee-accounting-export"
    assert json["version"] == 1
    assert json["from"] == "2027-02-01"
    assert [%{"number" => "I-000001"}, %{"gross_cents" => -2000, "sign" => -1}] = json["documents"]
    assert [%{"amount_cents" => 12_000}] = json["payments"]
  end

  test "every configured format describes itself and accepts its defaults" do
    for module <- Application.fetch_env!(:palee, :fiscal_accounting_export_formats) do
      description = module.describe()
      assert description.id == module.id()
      assert {:ok, _options} = module.normalize_options(%{})
      assert description.file_extension in ["csv", "json"]
    end
  end
end
