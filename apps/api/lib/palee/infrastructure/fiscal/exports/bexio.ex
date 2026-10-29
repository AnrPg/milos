defmodule Palee.Infrastructure.Fiscal.Exports.Bexio do
  @moduledoc """
  bexio manual bookings import (ADR-245): a semicolon-separated UTF-8 CSV
  with `Datum;Belegnummer;Buchungstext;SollKonto;HabenKonto;Betrag;MWST;
  Währung`, one booking per document and VAT rate. bexio books gross
  amounts (VAT included) and splits the VAT by the tax code, so `Betrag`
  is the gross amount and `MWST` the bexio code of the rate. Credit notes
  swap debit and credit account.

  Accounts default to the Swiss SME chart (KMU-Kontenrahmen): 1000 cash,
  1020 bank, 1100 receivables, 3400 revenue from services. Tax codes
  default to bexio's sales tax codes of the 2024 Swiss rates (UN81 8.1 %,
  UN26 2.6 %, UN38 3.8 %); both are configurable per tax category.
  """

  @behaviour Palee.Fiscal.Ports.AccountingExportFormat

  alias Palee.Fiscal.Domain.{ExportCsv, ExportEntries, ExportOptions}

  @columns ~w(Datum Belegnummer Buchungstext SollKonto HabenKonto Betrag MWST Währung)

  @categories ~w(standard reduced second_reduced super_reduced special zero exempt sales_tax)

  @options [
    %{key: "revenue_account", type: "string", default: "3400", description: "Revenue account"},
    %{
      key: "revenue_accounts",
      type: "map",
      keys: @categories,
      default: %{},
      description: "Revenue account per tax category, overriding revenue_account"
    },
    %{
      key: "tax_codes",
      type: "map",
      keys: @categories,
      default: %{},
      description: "bexio tax code per tax category (default UN<rate>, none when exempt)"
    },
    %{key: "cash_account", type: "string", default: "1000", description: "Cash account"},
    %{key: "bank_account", type: "string", default: "1020", description: "Bank account"},
    %{
      key: "receivable_account",
      type: "string",
      default: "1100",
      description: "Receivables account for invoices to be paid"
    },
    %{
      key: "include_payments",
      type: "boolean",
      default: false,
      description: "Also book Finance payments from receivables to cash or bank"
    }
  ]

  @impl true
  def id, do: "bexio"

  @impl true
  def describe do
    %{
      id: id(),
      name: "bexio",
      description: "Manual bookings CSV (gross amounts with the bexio VAT code).",
      file_extension: "csv",
      file_prefix: "bexio-buchungen",
      content_type: "text/csv; charset=utf-8",
      options: ExportOptions.public(@options)
    }
  end

  @impl true
  def normalize_options(options), do: ExportOptions.normalize(@options, options)

  def columns, do: @columns

  @impl true
  def render(%{entries: entries}, options) do
    rows =
      Enum.flat_map(entries.documents, &document_rows(&1, options)) ++
        if(options["include_payments"],
          do: Enum.map(entries.payments, &payment_row(&1, options)),
          else: []
        )

    skipped = if options["include_payments"], do: 0, else: length(entries.payments)

    {:ok,
     %{content: ExportCsv.encode([@columns | rows], separator: ";"), skipped: skipped}}
  end

  defp document_rows(document, options) do
    money = money_account(document, options)

    document.groups
    |> Enum.reject(&(&1.gross_cents == 0))
    |> Enum.map(fn group ->
      revenue =
        Map.get(options["revenue_accounts"], group.tax_category) || options["revenue_account"]

      {debit, credit} = if group.gross_cents < 0, do: {revenue, money}, else: {money, revenue}

      [
        ExportCsv.date(document.issue_date, :dmy_dot),
        document.number,
        ExportCsv.truncate(text(document), 80),
        debit,
        credit,
        ExportCsv.amount(abs(group.gross_cents)),
        tax_code(group, options),
        document.currency
      ]
    end)
  end

  defp money_account(%{kind: kind, payment_method: method}, options)
       when kind in ["invoice", "credit_note"] and method in [nil, "bank_transfer"],
       do: options["receivable_account"]

  defp money_account(%{payment_method: "cash"}, options), do: options["cash_account"]
  defp money_account(_document, options), do: options["bank_account"]

  defp text(document) do
    kind =
      case document.kind do
        "invoice" -> "Rechnung"
        "credit_note" -> "Gutschrift"
        _ -> "Quittung"
      end

    Enum.join(Enum.reject([kind, document.number, document.buyer[:name]], &is_nil/1), " ")
  end

  defp tax_code(group, options) do
    Map.get(options["tax_codes"], group.tax_category) ||
      if group.tax_category in ["exempt", "zero"] or group.rate_bp == 0,
        do: nil,
        else: "UN" <> String.replace(ExportEntries.percent(group.rate_bp), ".", "")
  end

  defp payment_row(payment, options) do
    money =
      if payment.payment_method == "cash",
        do: options["cash_account"],
        else: options["bank_account"]

    {debit, credit} =
      if payment.amount_cents < 0,
        do: {options["receivable_account"], money},
        else: {money, options["receivable_account"]}

    [
      ExportCsv.date(payment.paid_on, :dmy_dot),
      payment.reference,
      "Zahlung #{payment.reference}",
      debit,
      credit,
      ExportCsv.amount(abs(payment.amount_cents)),
      nil,
      payment.currency
    ]
  end
end
