defmodule Palee.Infrastructure.Fiscal.Exports.Datev do
  @moduledoc """
  DATEV Buchungsstapel (ADR-245): the "DATEV-Format" (EXTF) CSV that
  DATEV Kanzlei-Rechnungswesen and DATEV Unternehmen online import.

  * Windows-1252, `;` separated, CRLF, decimal comma; text in double quotes.
  * Row 1 is the EXTF header (header version 700, data category 21
    "Buchungsstapel", format version 9), row 2 the column names, then one
    booking per document and tax rate: the gross amount, debit (`S`) on
    the cash, bank or receivables account and credit on the revenue
    account; credit notes the other way round (`H`).
  * Revenue accounts are DATEV "Automatikkonten" by default (the VAT is
    split off by the account itself, no BU-Schlüssel); SKR03 and SKR04
    defaults can be overridden per tax category, as can BU keys.
  * Finance payments are optionally booked from the receivables account to
    the cash or bank account.

  Columns: DATEV Buchungsstapel format version 9 (120 fields), as used by
  the open-source ERPNext DATEV export, see ADR-245 for sources.
  """

  @behaviour Palee.Fiscal.Ports.AccountingExportFormat

  alias Palee.Fiscal.Domain.{ExportCsv, ExportOptions}

  @columns [
    "Umsatz (ohne Soll/Haben-Kz)",
    "Soll/Haben-Kennzeichen",
    "WKZ Umsatz",
    "Kurs",
    "Basis-Umsatz",
    "WKZ Basis-Umsatz",
    "Konto",
    "Gegenkonto (ohne BU-Schlüssel)",
    "BU-Schlüssel",
    "Belegdatum",
    "Belegfeld 1",
    "Belegfeld 2",
    "Skonto",
    "Buchungstext",
    "Postensperre",
    "Diverse Adressnummer",
    "Geschäftspartnerbank",
    "Sachverhalt",
    "Zinssperre",
    "Beleglink",
    "Beleginfo - Art 1",
    "Beleginfo - Inhalt 1",
    "Beleginfo - Art 2",
    "Beleginfo - Inhalt 2",
    "Beleginfo - Art 3",
    "Beleginfo - Inhalt 3",
    "Beleginfo - Art 4",
    "Beleginfo - Inhalt 4",
    "Beleginfo - Art 5",
    "Beleginfo - Inhalt 5",
    "Beleginfo - Art 6",
    "Beleginfo - Inhalt 6",
    "Beleginfo - Art 7",
    "Beleginfo - Inhalt 7",
    "Beleginfo - Art 8",
    "Beleginfo - Inhalt 8",
    "KOST1 - Kostenstelle",
    "KOST2 - Kostenstelle",
    "KOST-Menge",
    "EU-Mitgliedstaat u. USt-IdNr.",
    "EU-Steuersatz",
    "Abw. Versteuerungsart",
    "Sachverhalt L+L",
    "Funktionsergänzung L+L",
    "BU 49 Hauptfunktionstyp",
    "BU 49 Hauptfunktionsnummer",
    "BU 49 Funktionsergänzung",
    "Zusatzinformation - Art 1",
    "Zusatzinformation - Inhalt 1",
    "Zusatzinformation - Art 2",
    "Zusatzinformation - Inhalt 2",
    "Zusatzinformation - Art 3",
    "Zusatzinformation - Inhalt 3",
    "Zusatzinformation - Art 4",
    "Zusatzinformation - Inhalt 4",
    "Zusatzinformation - Art 5",
    "Zusatzinformation - Inhalt 5",
    "Zusatzinformation - Art 6",
    "Zusatzinformation - Inhalt 6",
    "Zusatzinformation - Art 7",
    "Zusatzinformation - Inhalt 7",
    "Zusatzinformation - Art 8",
    "Zusatzinformation - Inhalt 8",
    "Zusatzinformation - Art 9",
    "Zusatzinformation - Inhalt 9",
    "Zusatzinformation - Art 10",
    "Zusatzinformation - Inhalt 10",
    "Zusatzinformation - Art 11",
    "Zusatzinformation - Inhalt 11",
    "Zusatzinformation - Art 12",
    "Zusatzinformation - Inhalt 12",
    "Zusatzinformation - Art 13",
    "Zusatzinformation - Inhalt 13",
    "Zusatzinformation - Art 14",
    "Zusatzinformation - Inhalt 14",
    "Zusatzinformation - Art 15",
    "Zusatzinformation - Inhalt 15",
    "Zusatzinformation - Art 16",
    "Zusatzinformation - Inhalt 16",
    "Zusatzinformation - Art 17",
    "Zusatzinformation - Inhalt 17",
    "Zusatzinformation - Art 18",
    "Zusatzinformation - Inhalt 18",
    "Zusatzinformation - Art 19",
    "Zusatzinformation - Inhalt 19",
    "Zusatzinformation - Art 20",
    "Zusatzinformation - Inhalt 20",
    "Stück",
    "Gewicht",
    "Zahlweise",
    "Forderungsart",
    "Veranlagungsjahr",
    "Zugeordnete Fälligkeit",
    "Skontotyp",
    "Auftragsnummer",
    "Buchungstyp",
    "USt-Schlüssel (Anzahlungen)",
    "EU-Mitgliedstaat (Anzahlungen)",
    "Sachverhalt L+L (Anzahlungen)",
    "EU-Steuersatz (Anzahlungen)",
    "Erlöskonto (Anzahlungen)",
    "Herkunft-Kz",
    "Leerfeld",
    "KOST-Datum",
    "SEPA-Mandatsreferenz",
    "Skontosperre",
    "Gesellschaftername",
    "Beteiligtennummer",
    "Identifikationsnummer",
    "Zeichnernummer",
    "Postensperre bis",
    "Bezeichnung SoBil-Sachverhalt",
    "Kennzeichen SoBil-Buchung",
    "Festschreibung",
    "Leistungsdatum",
    "Datum Zuord. Steuerperiode",
    "Fälligkeit",
    "Generalumkehr (GU)",
    "Steuersatz",
    "Land"
  ]

  @categories ~w(standard reduced second_reduced super_reduced special zero exempt sales_tax small_business)

  @charts %{
    "SKR03" => %{
      revenue: %{
        "standard" => "8400",
        "reduced" => "8300",
        "second_reduced" => "8300",
        "super_reduced" => "8300",
        "special" => "8400",
        "sales_tax" => "8400",
        "zero" => "8120",
        "exempt" => "8100",
        "small_business" => "8195"
      },
      cash: "1000",
      bank: "1200",
      receivable: "1400"
    },
    "SKR04" => %{
      revenue: %{
        "standard" => "4400",
        "reduced" => "4300",
        "second_reduced" => "4300",
        "super_reduced" => "4300",
        "special" => "4400",
        "sales_tax" => "4400",
        "zero" => "4120",
        "exempt" => "4100",
        "small_business" => "4185"
      },
      cash: "1600",
      bank: "1800",
      receivable: "1200"
    }
  }

  @account ~r/^\d{1,9}$/

  @options [
    %{
      key: "chart",
      type: "enum",
      values: ["SKR03", "SKR04"],
      default: "SKR03",
      description: "Standard chart of accounts (Standardkontenrahmen)"
    },
    %{
      key: "consultant_number",
      type: "integer",
      range: {1001, 9_999_999},
      default: nil,
      description: "DATEV consultant number (Beraternummer), required"
    },
    %{
      key: "client_number",
      type: "integer",
      range: {1, 99_999},
      default: nil,
      description: "DATEV client number (Mandantennummer), required"
    },
    %{
      key: "account_length",
      type: "integer",
      range: {4, 8},
      default: 4,
      description: "Length of general ledger accounts (Sachkontenlänge)"
    },
    %{
      key: "fiscal_year_start_month",
      type: "integer",
      range: {1, 12},
      default: nil,
      description: "First month of the fiscal year (default: the business's legal identity)"
    },
    %{
      key: "revenue_accounts",
      type: "map",
      keys: @categories,
      default: %{},
      description:
        "Revenue account per tax category (small_business: Kleinunternehmer), overriding the chart default"
    },
    %{
      key: "bu_keys",
      type: "map",
      keys: @categories,
      default: %{},
      description: "BU-Schlüssel per tax category; leave empty for automatic accounts"
    },
    %{
      key: "cash_account",
      type: "string",
      format: @account,
      default: "",
      description: "Cash account (default SKR03 1000 / SKR04 1600)"
    },
    %{
      key: "bank_account",
      type: "string",
      format: @account,
      default: "",
      description: "Bank account for card, online and transfer payments (default 1200 / 1800)"
    },
    %{
      key: "receivable_account",
      type: "string",
      format: @account,
      default: "",
      description: "Receivables account for invoices to be paid (default 1400 / 1200)"
    },
    %{
      key: "include_payments",
      type: "boolean",
      default: false,
      description: "Also book Finance payments from receivables to cash or bank"
    },
    %{
      key: "dictation_code",
      type: "string",
      format: ~r/^[A-Za-z]{0,2}$/,
      default: "",
      description: "Diktatkürzel (two letters)"
    }
  ]

  @impl true
  def id, do: "datev"

  @impl true
  def describe do
    %{
      id: id(),
      name: "DATEV Buchungsstapel",
      description:
        "EXTF CSV for DATEV (Windows-1252, semicolons): one booking per document and VAT rate.",
      file_extension: "csv",
      file_prefix: "EXTF_Buchungsstapel",
      content_type: "text/csv; charset=windows-1252",
      options: ExportOptions.public(@options)
    }
  end

  @impl true
  def normalize_options(options), do: ExportOptions.normalize(@options, options)

  @doc "The 120 Buchungsstapel column names (format version 9)."
  def columns, do: @columns

  @doc "The default accounts of a chart (`SKR03`, `SKR04`)."
  def chart(name), do: Map.fetch!(@charts, name)

  @impl true
  def render(%{entries: entries} = context, options) do
    with :ok <- required(options) do
      accounts = accounts(options)
      seller = Map.get(context, :seller, %{})

      bookings =
        Enum.flat_map(entries.documents, &document_bookings(&1, accounts, seller, options)) ++
          if(options["include_payments"],
            do: Enum.map(entries.payments, &payment_booking(&1, accounts)),
            else: []
          )

      content =
        [header(context, options, seller), Enum.join(@columns, ";")]
        |> Enum.concat(Enum.map(bookings, &row/1))
        |> Enum.map_join("", &(&1 <> "\r\n"))
        |> ExportCsv.to_cp1252()

      {:ok, %{content: content, skipped: 0}}
    end
  end

  defp required(options) do
    errors =
      for key <- ["consultant_number", "client_number"], options[key] in [nil, ""], into: %{} do
        {"options.#{key}", :required}
      end

    if errors == %{}, do: :ok, else: {:error, {:invalid_fields, errors}}
  end

  defp accounts(options) do
    chart = chart(options["chart"])

    %{
      revenue: Map.merge(chart.revenue, options["revenue_accounts"] || %{}),
      bu: options["bu_keys"] || %{},
      cash: present(options["cash_account"]) || chart.cash,
      bank: present(options["bank_account"]) || chart.bank,
      receivable: present(options["receivable_account"]) || chart.receivable
    }
  end

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  # ── Header ────────────────────────────────────────────────────────────────

  defp header(context, options, seller) do
    from = context.from
    start_month = options["fiscal_year_start_month"] || seller[:fiscal_year_start_month] || 1
    year = if from.month >= start_month, do: from.year, else: from.year - 1
    fiscal_year_start = Date.new!(year, start_month, 1)

    [
      text("EXTF"),
      "700",
      "21",
      text("Buchungsstapel"),
      "9",
      timestamp(context.generated_at),
      "",
      text("RE"),
      text("Palee"),
      text(""),
      Integer.to_string(options["consultant_number"]),
      Integer.to_string(options["client_number"]),
      ExportCsv.date(fiscal_year_start, :yyyymmdd),
      Integer.to_string(options["account_length"]),
      ExportCsv.date(context.from, :yyyymmdd),
      ExportCsv.date(context.to, :yyyymmdd),
      text(
        ExportCsv.truncate(
          "Palee #{Date.to_iso8601(context.from)}-#{Date.to_iso8601(context.to)}",
          30
        )
      ),
      text(options["dictation_code"] || ""),
      "1",
      "0",
      "0",
      text(seller[:currency] || "EUR"),
      "",
      text(""),
      "",
      "",
      text(String.slice(options["chart"], 3, 2)),
      "",
      "",
      "",
      text("")
    ]
    |> Enum.join(";")
  end

  defp timestamp(%DateTime{} = at) do
    at = DateTime.truncate(at, :millisecond)
    {millis, _precision} = at.microsecond

    ExportCsv.date(DateTime.to_date(at), :yyyymmdd) <>
      Enum.map_join([at.hour, at.minute, at.second], &pad2/1) <>
      String.pad_leading(Integer.to_string(div(millis, 1000)), 3, "0")
  end

  defp pad2(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  # ── Bookings ──────────────────────────────────────────────────────────────

  defp document_bookings(document, accounts, seller, _options) do
    debit = debit_account(document, accounts)
    small_business? = seller[:vat_scheme] == "small_business"

    document.groups
    |> Enum.reject(&(&1.gross_cents == 0))
    |> Enum.map(fn group ->
      category =
        if small_business? and group.tax_category == "exempt",
          do: "small_business",
          else: group.tax_category

      %{
        amount_cents: group.gross_cents,
        currency: document.currency,
        account: debit,
        contra_account: Map.get(accounts.revenue, category) || accounts.revenue["standard"],
        bu_key: Map.get(accounts.bu, category),
        date: document.issue_date,
        reference: document.number,
        reference_2: document.corrects_number,
        text: booking_text(document)
      }
    end)
  end

  defp debit_account(%{kind: kind, payment_method: method}, accounts)
       when kind in ["invoice", "credit_note"] and method in [nil, "bank_transfer"],
       do: accounts.receivable

  defp debit_account(%{payment_method: "cash"}, accounts), do: accounts.cash
  defp debit_account(_document, accounts), do: accounts.bank

  defp booking_text(document) do
    kind =
      case document.kind do
        "invoice" -> "Rechnung"
        "credit_note" -> "Gutschrift"
        _ -> "Beleg"
      end

    [kind, document.number, document.buyer[:name]]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp payment_booking(payment, accounts) do
    %{
      amount_cents: payment.amount_cents,
      currency: payment.currency,
      account: if(payment.payment_method == "cash", do: accounts.cash, else: accounts.bank),
      contra_account: accounts.receivable,
      bu_key: nil,
      date: payment.paid_on,
      reference: payment.reference,
      reference_2: nil,
      text: "Zahlung #{payment.reference}"
    }
  end

  defp row(booking) do
    values = %{
      "Umsatz (ohne Soll/Haben-Kz)" => ExportCsv.amount(abs(booking.amount_cents), ","),
      "Soll/Haben-Kennzeichen" => text(if(booking.amount_cents < 0, do: "H", else: "S")),
      "WKZ Umsatz" => text(booking.currency),
      "Konto" => booking.account,
      "Gegenkonto (ohne BU-Schlüssel)" => booking.contra_account,
      "BU-Schlüssel" => booking.bu_key && text(booking.bu_key),
      "Belegdatum" => ExportCsv.date(booking.date, :ddmm),
      "Belegfeld 1" => text(belegfeld(booking.reference)),
      "Belegfeld 2" => booking.reference_2 && text(belegfeld(booking.reference_2)),
      "Buchungstext" => text(ExportCsv.truncate(booking.text, 60))
    }

    Enum.map_join(@columns, ";", &(Map.get(values, &1) || ""))
  end

  # Belegfeld 1 holds at most 36 of `A-Z 0-9 $ & % * + - /` (and lower case).
  defp belegfeld(nil), do: ""

  defp belegfeld(reference) do
    reference
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9$&%*+\-\/]/, "")
    |> String.slice(0, 36)
  end

  defp text(value), do: "\"" <> String.replace(to_string(value), "\"", "\"\"") <> "\""
end
