defmodule Palee.Fiscal.Ports.SalesTaxCalculator do
  @moduledoc """
  The tax rate of a sale line (ADR-244).

  The configured adapter (`:fiscal_sales_tax_calculator`) answers for every
  country: VAT countries from `Fiscal.Domain.VatRates`, US sales tax from
  wherever the adapter looks it up. `RateTableSalesTaxCalculator` uses the
  rates the gym keeps itself (state and ZIP code); a Stripe Tax or Avalara
  adapter can replace it without touching callers.

  `place` is where the service is supplied: the gym's own address
  (`region` = state, `postal_code` = ZIP code) for memberships and sales at
  the desk.
  """

  @type context :: map()
  @type query :: %{
          required(:country_code) => String.t(),
          required(:tax_category) => String.t(),
          required(:date) => Date.t(),
          optional(:region) => String.t() | nil,
          optional(:postal_code) => String.t() | nil
        }

  @doc "`{:ok, rate_bp}` or `{:error, reason}`."
  @callback rate(context(), query()) :: {:ok, non_neg_integer()} | {:error, atom()}
end
