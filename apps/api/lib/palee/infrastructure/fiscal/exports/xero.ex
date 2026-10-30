defmodule Palee.Infrastructure.Fiscal.Exports.Xero do
  @moduledoc """
  Xero sales invoice import (ADR-245): the 27-column CSV of Xero's
  "Import sales invoices" template, one row per document line; the rows of
  a document share its `*InvoiceNumber`. Credit notes have a negative
  `*UnitAmount` (Xero imports them as credit notes). A discounted line is
  written as quantity 1 at its discounted amount, since Xero's `Discount`
  is a percentage.

  Amounts are as printed on the document: tax inclusive when the document's
  prices include tax (choose "Tax inclusive" when importing). Dates follow
  the Xero organisation's region (`date_format`).
  """

  @behaviour Palee.Fiscal.Ports.AccountingExportFormat

  alias Palee.Fiscal.Domain.{ExportCsv, ExportEntries, ExportOptions}

  @columns ~w(*ContactName EmailAddress POAddressLine1 POAddressLine2 POAddressLine3
              POAddressLine4 POCity PORegion POPostalCode POCountry *InvoiceNumber Reference
              *InvoiceDate *DueDate InventoryItemCode *Description *Quantity *UnitAmount Discount
              *AccountCode *TaxType TrackingName1 TrackingOption1 TrackingName2 TrackingOption2
              Currency BrandingTheme)

  @categories ~w(standard reduced second_reduced super_reduced special zero exempt sales_tax)

  @options [
    %{
      key: "date_format",
      type: "enum",
      values: ["dmy", "mdy", "iso"],
      default: "dmy",
      description: "Date layout of the Xero organisation's region"
    },
    %{
      key: "account_code",
      type: "string",
      default: "200",
      description: "Sales account code (Xero default chart: 200 Sales)"
    },
    %{
      key: "account_codes",
      type: "map",
      keys: @categories,
      default: %{},
      description: "Account code per tax category, overriding account_code"
    },
    %{
      key: "tax_types",
      type: "map",
      keys: @categories,
      default: %{},
      description:
        "Xero tax rate name per tax category (default: \"<rate>% (VAT on Income)\", Zero Rated Income, Exempt Income)"
    },
    %{
      key: "due_days",
      type: "integer",
      range: {0, 365},
      default: 0,
      description: "Days from the issue date to the due date"
    },
    %{
      key: "walk_in_contact",
      type: "string",
      default: "Cash sales",
      description: "Contact name for receipts without a named customer"
    }
  ]

  @impl true
  def id, do: "xero"

  @impl true
  def describe do
    %{
      id: id(),
      name: "Xero",
      description: "Sales invoice import CSV (one row per line, amounts tax inclusive).",
      file_extension: "csv",
      file_prefix: "xero-sales-invoices",
      content_type: "text/csv; charset=utf-8",
      options: ExportOptions.public(@options)
    }
  end

  @impl true
  def normalize_options(options), do: ExportOptions.normalize(@options, options)

  def columns, do: @columns

  @impl true
  def render(%{entries: entries}, options) do
    rows = Enum.flat_map(entries.documents, &document_rows(&1, options))
    {:ok, %{content: ExportCsv.encode([@columns | rows]), skipped: length(entries.payments)}}
  end

  defp document_rows(document, options) do
    date = date(document.issue_date, options)
    due = date(Date.add(document.issue_date, options["due_days"]), options)
    buyer = document.buyer

    Enum.map(document.lines, fn line ->
      {quantity, unit} = quantity_and_unit(line, document.sign)

      [
        buyer[:name] || options["walk_in_contact"],
        buyer[:email],
        address_line(buyer),
        nil,
        nil,
        nil,
        buyer[:city],
        nil,
        buyer[:postal_code],
        buyer[:country_code],
        document.number,
        document.corrects_number,
        date,
        due,
        nil,
        line.description,
        Integer.to_string(quantity),
        ExportCsv.amount(unit),
        nil,
        Map.get(options["account_codes"], line.tax_category) || options["account_code"],
        tax_type(line, options),
        nil,
        nil,
        nil,
        nil,
        document.currency,
        nil
      ]
    end)
  end

  defp quantity_and_unit(%{discount_cents: 0, quantity: quantity, unit_price_cents: unit}, sign)
       when is_integer(quantity) and is_integer(unit),
       do: {quantity, sign * unit}

  defp quantity_and_unit(line, _sign), do: {1, line.amount_cents}

  defp address_line(buyer) do
    case Enum.reject([buyer[:street], buyer[:building_number]], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  defp tax_type(line, options) do
    Map.get(options["tax_types"], line.tax_category) ||
      case line.tax_category do
        "exempt" -> "Exempt Income"
        "zero" -> "Zero Rated Income"
        _ -> "#{ExportEntries.percent(line.rate_bp)}% (VAT on Income)"
      end
  end

  defp date(date, %{"date_format" => format}),
    do: ExportCsv.date(date, Map.fetch!(%{"dmy" => :dmy, "mdy" => :mdy, "iso" => :iso}, format))
end
