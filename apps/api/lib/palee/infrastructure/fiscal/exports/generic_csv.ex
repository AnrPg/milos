defmodule Palee.Infrastructure.Fiscal.Exports.GenericCsv do
  @moduledoc """
  Palee's own flat CSV (ADR-245): one row per document line
  (`record_type` `line`) and, when there are any, one row per Finance
  payment (`record_type` `payment`). Amounts are signed (credit notes
  negative) in integer cents or as decimals; the column list is stable.
  """

  @behaviour Palee.Fiscal.Ports.AccountingExportFormat

  alias Palee.Fiscal.Domain.{ExportCsv, ExportOptions}

  @columns ~w(record_type document_id number kind issue_date currency payment_method
              corrects_number buyer_name buyer_tax_id buyer_vat_number buyer_country_code
              line_position description quantity unit_price tax_category rate_bp
              exemption_reason net tax gross)

  @options [
    %{
      key: "separator",
      type: "enum",
      values: [",", ";", "tab"],
      default: ",",
      description: "Field separator"
    },
    %{
      key: "amounts",
      type: "enum",
      values: ["cents", "decimal_point", "decimal_comma"],
      default: "cents",
      description: "Integer cents, or decimals with a point or a comma"
    }
  ]

  @impl true
  def id, do: "csv"

  @impl true
  def describe do
    %{
      id: id(),
      name: "CSV",
      description: "Palee's flat CSV: one row per document line and per payment.",
      file_extension: "csv",
      file_prefix: "palee-accounting",
      content_type: "text/csv; charset=utf-8",
      options: ExportOptions.public(@options)
    }
  end

  @impl true
  def normalize_options(options), do: ExportOptions.normalize(@options, options)

  def columns, do: @columns

  @impl true
  def render(%{entries: entries}, options) do
    money = money(options["amounts"])

    rows =
      Enum.flat_map(entries.documents, &document_rows(&1, money)) ++
        Enum.map(entries.payments, &payment_row(&1, money))

    separator = if options["separator"] == "tab", do: "\t", else: options["separator"]

    {:ok, %{content: ExportCsv.encode([@columns | rows], separator: separator), skipped: 0}}
  end

  defp money("cents"), do: &Integer.to_string/1
  defp money("decimal_point"), do: &ExportCsv.amount(&1, ".")
  defp money("decimal_comma"), do: &ExportCsv.amount(&1, ",")

  defp document_rows(document, money) do
    buyer = document.buyer

    Enum.map(document.lines, fn line ->
      [
        "line",
        document.id,
        document.number,
        document.kind,
        Date.to_iso8601(document.issue_date),
        document.currency,
        document.payment_method,
        document.corrects_number,
        buyer[:name],
        buyer[:tax_id],
        buyer[:vat_number],
        buyer[:country_code],
        line.position,
        line.description,
        line.quantity,
        line.unit_price_cents && money.(line.unit_price_cents),
        line.tax_category,
        line.rate_bp,
        line.exemption_reason,
        money.(line.net_cents),
        money.(line.tax_cents),
        money.(line.gross_cents)
      ]
    end)
  end

  defp payment_row(payment, money) do
    [
      "payment",
      payment.id,
      payment.reference,
      "payment",
      payment.paid_on && Date.to_iso8601(payment.paid_on),
      payment.currency,
      payment.payment_method,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      money.(payment.amount_cents)
    ]
  end
end
