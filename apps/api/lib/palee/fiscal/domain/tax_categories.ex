defmodule Palee.Fiscal.Domain.TaxCategories do
  @moduledoc """
  The tax category of what a gym sells (ADR-244): a membership package, a
  shop product, a shop variant.

    * a category is one of `VatRates.categories/0`; for a gym whose legal
      identity is saved it must be one its country offers
      (`VatRates.categories/1`), so a German gym cannot pick `special`;
    * `exempt` needs the reason printed on the document (the article of the
      VAT law), at most 300 characters;
    * nothing chosen means `standard` (`sales_tax` in the US) on a package
      or a product, and "as its product" on a variant (`effective/3`).

  A business that is not VAT registered (small business scheme) prints
  every line as exempt with its country's legal mention
  (`small_business_reason/1`), whatever the category says.
  """

  alias Palee.Fiscal.Domain.VatRates

  @max_reason 300
  @default "standard"

  # The mention a small business prints instead of VAT, in the country's
  # document language. Sources in ADR-244.
  @small_business_reasons %{
    "GR" => "Απαλλαγή από ΦΠΑ, άρθρο 39 του Κώδικα ΦΠΑ (ειδικό καθεστώς μικρών επιχειρήσεων)",
    "CY" => "Not registered for VAT (turnover below the registration threshold)",
    "DE" => "Gemäß § 19 UStG wird keine Umsatzsteuer berechnet (Kleinunternehmerregelung)",
    "AT" => "Umsatzsteuerfrei aufgrund der Kleinunternehmerregelung gemäß § 6 Abs. 1 Z 27 UStG",
    "CH" => "Nicht mehrwertsteuerpflichtig (Art. 10 Abs. 2 MWSTG)",
    "LI" => "Nicht mehrwertsteuerpflichtig (Art. 10 Abs. 2 MWSTG)",
    "LU" => "Franchise de TVA, article 57 de la loi TVA (petites entreprises)",
    "FR" => "TVA non applicable, art. 293 B du CGI",
    "MC" => "TVA non applicable, art. 293 B du CGI",
    "BE" => "Régime particulier de franchise des petites entreprises (art. 56bis du Code TVA)",
    "GB" => "Not registered for VAT",
    "US" => "No sales tax collected"
  }

  @doc "The category of an item that names none: `standard`, `sales_tax` in the US."
  def default(country \\ nil)
  def default("US"), do: "sales_tax"
  def default(_country), do: @default

  def max_reason, do: @max_reason

  @doc """
  `:ok` or `{:error, {:invalid_fields, %{field => reason}}}`. `country` is
  the seller's country, or nil when no legal identity is saved yet (then
  every known category is accepted).
  """
  def check(country, category, exemption_reason) do
    reason = clean(exemption_reason)

    errors =
      %{}
      |> check_category(country, category)
      |> check_reason(category, reason)

    if errors == %{}, do: :ok, else: {:error, {:invalid_fields, errors}}
  end

  defp check_category(errors, _country, nil), do: errors

  defp check_category(errors, country, category) do
    cond do
      category not in VatRates.categories() -> Map.put(errors, :tax_category, :invalid)
      is_nil(country) -> errors
      category in VatRates.categories(country) -> errors
      true -> Map.put(errors, :tax_category, :not_available_in_country)
    end
  end

  defp check_reason(errors, "exempt", nil), do: Map.put(errors, :exemption_reason, :required)

  defp check_reason(errors, _category, reason) when is_binary(reason) do
    if String.length(reason) > @max_reason,
      do: Map.put(errors, :exemption_reason, :too_long),
      else: errors
  end

  defp check_reason(errors, _category, _reason), do: errors

  @doc "The category that applies: the item's own, else its parent's, else `default/1`."
  def effective(own, parent \\ nil, country \\ nil),
    do: clean(own) || clean(parent) || default(country)

  @doc "The legal mention of a small business in `country` (nil if unknown)."
  def small_business_reason(country), do: Map.get(@small_business_reasons, country)

  @doc false
  def clean(nil), do: nil

  def clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def clean(_value), do: nil
end
