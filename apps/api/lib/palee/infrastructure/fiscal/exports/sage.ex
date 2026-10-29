defmodule Palee.Infrastructure.Fiscal.Exports.Sage do
  @moduledoc """
  Sage 50 Accounts "Audit trail transactions" import (ADR-245), which
  Sage Business Cloud Accounting migrations accept too: one row per
  document and tax rate, `SI` (sales invoice) or `SC` (sales credit) with
  positive net and tax amounts, dates `DD/MM/YYYY`. Finance payments can
  be added as `SA` (sales receipt on account) rows.

  Nominal codes and tax codes are configurable; the defaults follow the
  Sage 50 UK chart (4000 Sales, 1200 bank, 1230 petty cash) and its VAT
  codes (T1 standard, T5 reduced, T0 zero rated, T2 exempt, T9 outside
  the scope of VAT).
  """

  @behaviour Palee.Fiscal.Ports.AccountingExportFormat

  alias Palee.Fiscal.Domain.{ExportCsv, ExportOptions}

  @columns [
    "Type",
    "Account Reference",
    "Nominal A/C Ref",
    "Department Code",
    "Date",
    "Reference",
    "Details",
    "Net Amount",
    "Tax Code",
    "Tax Amount",
    "Exchange Rate",
    "Extra Reference",
    "User Name",
    "Project Refn",
    "Cost Code Refn"
  ]

  @categories ~w(standard reduced second_reduced super_reduced special zero exempt sales_tax)

  @tax_codes %{
    "standard" => "T1",
    "reduced" => "T5",
    "second_reduced" => "T5",
    "super_reduced" => "T5",
    "special" => "T1",
    "sales_tax" => "T1",
    "zero" => "T0",
    "exempt" => "T2"
  }

  @options [
    %{
      key: "customer_account",
      type: "string",
      default: "PALEE",
      description: "Customer account reference all sales are posted to (must exist in Sage)"
    },
    %{
      key: "nominal_code",
      type: "string",
      default: "4000",
      description: "Sales nominal code"
    },
    %{
      key: "nominal_codes",
      type: "map",
      keys: @categories,
      default: %{},
      description: "Sales nominal code per tax category, overriding nominal_code"
    },
    %{
      key: "tax_codes",
      type: "map",
      keys: @categories,
      default: %{},
      description: "Sage tax code per tax category (default T1, T5, T0, T2)"
    },
    %{
      key: "department",
      type: "integer",
      range: {0, 999},
      default: 0,
      description: "Department code"
    },
    %{
      key: "include_payments",
      type: "boolean",
      default: false,
      description: "Also post Finance payments as sales receipts on account (SA)"
    },
    %{
      key: "bank_nominal_code",
      type: "string",
      default: "1200",
      description: "Bank nominal code for payments"
    },
    %{
      key: "cash_nominal_code",
      type: "string",
      default: "1230",
      description: "Cash nominal code for cash payments"
    }
  ]

  @impl true
  def id, do: "sage"

  @impl true
  def describe do
    %{
      id: id(),
      name: "Sage 50 / Sage Business Cloud",
      description: "Audit trail transactions CSV: SI/SC per document and VAT rate.",
      file_extension: "csv",
      file_prefix: "sage-audit-trail",
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
    {:ok, %{content: ExportCsv.encode([@columns | rows]), skipped: skipped}}
  end

  defp document_rows(document, options) do
    type = if document.sign < 0, do: "SC", else: "SI"

    document.groups
    |> Enum.reject(&(&1.gross_cents == 0))
    |> Enum.map(fn group ->
      [
        type,
        options["customer_account"],
        Map.get(options["nominal_codes"], group.tax_category) || options["nominal_code"],
        options["department"],
        ExportCsv.date(document.issue_date, :dmy),
        ExportCsv.truncate(document.number, 30),
        ExportCsv.truncate(details(document), 60),
        ExportCsv.amount(abs(group.net_cents)),
        Map.get(options["tax_codes"], group.tax_category) ||
          Map.get(@tax_codes, group.tax_category, "T9"),
        ExportCsv.amount(abs(group.tax_cents)),
        nil,
        ExportCsv.truncate(document.corrects_number, 30),
        nil,
        nil,
        nil
      ]
    end)
  end

  defp details(document), do: document.buyer[:name] || "Palee #{document.kind}"

  defp payment_row(payment, options) do
    [
      if(payment.amount_cents < 0, do: "SP", else: "SA"),
      options["customer_account"],
      if(payment.payment_method == "cash",
        do: options["cash_nominal_code"],
        else: options["bank_nominal_code"]
      ),
      options["department"],
      ExportCsv.date(payment.paid_on, :dmy),
      ExportCsv.truncate(payment.reference, 30),
      ExportCsv.truncate("Payment #{payment.reference}", 60),
      ExportCsv.amount(abs(payment.amount_cents)),
      "T9",
      "0.00",
      nil,
      nil,
      nil,
      nil,
      nil
    ]
  end
end
