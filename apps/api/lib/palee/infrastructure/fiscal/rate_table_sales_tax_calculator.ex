defmodule Palee.Infrastructure.Fiscal.RateTableSalesTaxCalculator do
  @moduledoc """
  `Fiscal.Ports.SalesTaxCalculator` from tables (ADR-244): VAT rates by
  country, category and date (`VatRates`), and US sales tax from the rates
  the gym keeps by state and ZIP code (`fiscal_sales_tax_rates`).
  """

  @behaviour Palee.Fiscal.Ports.SalesTaxCalculator

  alias Palee.Fiscal.Domain.{SalesTaxRateTable, VatRates}
  alias Palee.Fiscal.TaxStore

  @impl true
  def rate(context, %{country_code: "US", tax_category: "sales_tax"} = query) do
    context
    |> TaxStore.list_sales_tax_rates()
    |> SalesTaxRateTable.lookup(query[:region], query[:postal_code] || "")
  end

  def rate(_context, %{country_code: country, tax_category: category, date: %Date{} = date}),
    do: VatRates.rate(country, category, date)
end
