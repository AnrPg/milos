defmodule Palee.Infrastructure.Fiscal.Exports.QuickBooks do
  @moduledoc """
  QuickBooks Online invoice import (ADR-245): the CSV of "Import data ›
  Invoices", one row per document line; the rows of a document share its
  invoice number. Receipts are imported as invoices too (they are already
  paid: the payment method is in `Memo`). QuickBooks' import takes neither
  credit memos nor negative amounts, so credit notes are left out and
  counted as skipped.

  Item amounts are net of tax with the line's tax in `Item Tax Amount`;
  `Item Tax Code` is the QuickBooks tax code per tax category (US:
  `TAX`/`NON`). At most 100 invoices and 1,000 rows go in one upload.
  """

  @behaviour Palee.Fiscal.Ports.AccountingExportFormat

  alias Palee.Fiscal.Domain.{ExportCsv, ExportEntries, ExportOptions}

  @columns [
    "Invoice No.",
    "Customer",
    "Invoice Date",
    "Due Date",
    "Terms",
    "Location",
    "Memo",
    "Item(Product/Service)",
    "Item Description",
    "Item Quantity",
    "Item Rate",
    "Item Amount",
    "Item Tax Code",
    "Item Tax Amount",
    "Currency",
    "Service Date"
  ]

  @categories ~w(standard reduced second_reduced super_reduced special zero exempt sales_tax)

  @options [
    %{
      key: "date_format",
      type: "enum",
      values: ["mdy", "dmy", "iso"],
      default: "mdy",
      description: "Date layout of the QuickBooks company"
    },
    %{
      key: "item",
      type: "string",
      default: "Sales",
      description: "Product/service name for every line"
    },
    %{
      key: "items",
      type: "map",
      keys: @categories,
      default: %{},
      description: "Product/service name per tax category, overriding item"
    },
    %{
      key: "tax_codes",
      type: "map",
      keys: @categories,
      default: %{},
      description:
        "QuickBooks tax code per tax category (default US: TAX, exempt NON; else \"<rate>%\")"
    },
    %{
      key: "terms",
      type: "string",
      default: "Due on receipt",
      description: "Payment terms"
    },
    %{
      key: "walk_in_customer",
      type: "string",
      default: "Cash sales",
      description: "Customer for receipts without a named customer"
    }
  ]

  @impl true
  def id, do: "quickbooks"

  @impl true
  def describe do
    %{
      id: id(),
      name: "QuickBooks Online",
      description:
        "Invoice import CSV (one row per line, net amounts); credit notes are skipped.",
      file_extension: "csv",
      file_prefix: "quickbooks-invoices",
      content_type: "text/csv; charset=utf-8",
      options: ExportOptions.public(@options)
    }
  end

  @impl true
  def normalize_options(options), do: ExportOptions.normalize(@options, options)

  def columns, do: @columns

  @impl true
  def render(%{entries: entries}, options) do
    {credit_notes, documents} = Enum.split_with(entries.documents, &(&1.kind == "credit_note"))
    rows = Enum.flat_map(documents, &document_rows(&1, options))

    {:ok,
     %{
       content: ExportCsv.encode([@columns | rows]),
       skipped: length(credit_notes) + length(entries.payments)
     }}
  end

  defp document_rows(document, options) do
    date = date(document.issue_date, options)

    Enum.map(document.lines, fn line ->
      [
        document.number,
        document.buyer[:name] || options["walk_in_customer"],
        date,
        date,
        options["terms"],
        nil,
        memo(document),
        Map.get(options["items"], line.tax_category) || options["item"],
        line.description,
        Integer.to_string(line.quantity || 1),
        rate(line.net_cents, line.quantity || 1),
        ExportCsv.amount(line.net_cents),
        tax_code(line, document, options),
        ExportCsv.amount(line.tax_cents),
        document.currency,
        date
      ]
    end)
  end

  defp memo(%{payment_method: nil}), do: nil
  defp memo(%{payment_method: method}), do: "Paid: #{method}"

  @doc false
  # The unit rate with up to four decimals (`rate(1000, 3)` → "3.3333").
  def rate(cents, quantity) when quantity > 1 do
    ten_thousandths = div(cents * 100 + div(quantity, 2), quantity)
    whole = div(ten_thousandths, 10_000)
    fraction = rem(ten_thousandths, 10_000)

    digits =
      fraction
      |> Integer.to_string()
      |> String.pad_leading(4, "0")
      |> String.trim_trailing("0")
      |> String.pad_trailing(2, "0")

    "#{whole}.#{digits}"
  end

  def rate(cents, _quantity), do: ExportCsv.amount(cents)

  defp tax_code(line, document, options) do
    Map.get(options["tax_codes"], line.tax_category) ||
      case {document.country_code, line.tax_category} do
        {"US", "exempt"} -> "NON"
        {"US", _category} -> "TAX"
        {_country, "exempt"} -> "Exempt"
        {_country, _category} -> "#{ExportEntries.percent(line.rate_bp)}%"
      end
  end

  defp date(date, %{"date_format" => format}),
    do: ExportCsv.date(date, Map.fetch!(%{"dmy" => :dmy, "mdy" => :mdy, "iso" => :iso}, format))
end
