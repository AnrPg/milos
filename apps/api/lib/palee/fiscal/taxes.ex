defmodule Palee.Fiscal.Taxes do
  @moduledoc """
  The tax engine of the Fiscal context (ADR-244): which tax categories a
  gym may give what it sells, the rate of a sale line through the
  `Fiscal.Ports.SalesTaxCalculator` port, and the US sales tax rates a gym
  keeps itself.

  Request lines for `Palee.Fiscal.issue/4` come from
  `Palee.Fiscal.Domain.SaleLines`; `apply_sales_tax/4` then fills the rate
  of US `sales_tax` lines.
  """

  alias Palee.Fiscal
  alias Palee.Fiscal.{FiscalStore, TaxStore}
  alias Palee.Fiscal.Domain.{SalesTaxRateTable, TaxCategories, VatRates}

  @doc "The configured sales tax calculator."
  def calculator, do: Application.fetch_env!(:palee, :fiscal_sales_tax_calculator)

  @doc "Every tax category Palee knows (`VatRates.categories/0`)."
  def all_categories, do: VatRates.categories()

  @doc "Longest exemption reason printed on a document."
  def max_exemption_reason, do: TaxCategories.max_reason()

  @doc """
  `%{country, categories, default}`: the categories the gym's country
  offers (every known one before the legal identity is saved).
  """
  def categories(context) do
    country = country(context)

    %{
      country: country,
      categories: if(country, do: VatRates.categories(country), else: VatRates.categories()),
      default: TaxCategories.default(country)
    }
  end

  @doc """
  Checks a category (and its exemption reason) for something the gym
  sells: `:ok` or `{:error, {:invalid_fields, errors}}`.
  """
  def check_category(context, category, exemption_reason),
    do: TaxCategories.check(country(context), category, exemption_reason)

  @doc "The US sales tax rates the gym keeps, and whether they apply to it."
  def sales_tax_rates(context) do
    %{
      applies: country(context) == "US",
      rates: TaxStore.list_sales_tax_rates(context),
      states: SalesTaxRateTable.states()
    }
  end

  @doc """
  Replaces the gym's US sales tax rate table and journals it (ADR-242).
  `{:ok, %{applies, rates, states}}`, `{:error, :sales_tax_not_applicable}`
  for a gym outside the US, or `{:error, {:invalid_fields, errors}}`.
  """
  def save_sales_tax_rates(context, rows, actor_id, %DateTime{} = now) do
    with :ok <- (country(context) == "US" && :ok) || {:error, :sales_tax_not_applicable},
         {:ok, rows} <- SalesTaxRateTable.normalize(rows),
         {:ok, _rates} <-
           FiscalStore.transaction(context, fn ->
             with {:ok, rates} <- TaxStore.replace_sales_tax_rates(context, rows, actor_id),
                  {:ok, _entry} <-
                    Fiscal.append(context, %{
                      event_type: "sales_tax_rates_saved",
                      subject_type: "sales_tax_rates",
                      actor_id: actor_id,
                      occurred_at: now,
                      payload: %{rates: rows}
                    }) do
               {:ok, rates}
             end
           end) do
      {:ok, sales_tax_rates(context)}
    end
  end

  @doc """
  The rate of `category` on `date` at `place` (`%{region, postal_code}`,
  default the gym's own address). `{:ok, rate_bp}` or `{:error, reason}`.
  """
  def rate(context, category, %Date{} = date, place \\ nil) do
    case FiscalStore.get_identity(context) do
      nil -> {:error, :fiscal_identity_missing}
      identity -> lookup(context, identity, category, date, place)
    end
  end

  @doc """
  Fills `rate_bp` of every `sales_tax` line without one (US), from the
  calculator. `{:ok, lines}` or `{:error, reason}` (e.g.
  `:sales_tax_rate_missing` when the gym has no rate for its place).
  """
  def apply_sales_tax(context, lines, %Date{} = date, place \\ nil) do
    if Enum.any?(lines, &needs_rate?/1) do
      with identity when is_map(identity) <-
             FiscalStore.get_identity(context) || {:error, :fiscal_identity_missing},
           {:ok, rate} <- lookup(context, identity, "sales_tax", date, place) do
        {:ok,
         Enum.map(lines, fn line ->
           if needs_rate?(line), do: Map.put(line, :rate_bp, rate), else: line
         end)}
      end
    else
      {:ok, lines}
    end
  end

  defp needs_rate?(line), do: line[:tax_category] == "sales_tax" and is_nil(line[:rate_bp])

  defp lookup(context, identity, category, date, place) do
    place = place || %{}

    calculator().rate(context, %{
      country_code: identity.country_code,
      tax_category: category,
      date: date,
      region: place[:region] || identity[:region],
      postal_code: place[:postal_code] || identity[:postal_code]
    })
  end

  defp country(context) do
    case FiscalStore.get_identity(context) do
      %{country_code: country} -> country
      nil -> nil
    end
  end
end
