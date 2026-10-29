defmodule Palee.Fiscal.TaxCategoryChangeset do
  @moduledoc """
  Changeset checks of the `tax_category` and `exemption_reason` columns
  that packages, shop products and shop variants share (ADR-244): a known
  category, a reason with `exempt` (at most 300 characters), and no stale
  reason on any other category. Whether the business's country offers the
  category is checked by the use case (`Palee.Fiscal.Taxes.check_category/3`),
  which knows the country.
  """

  import Ecto.Changeset

  alias Palee.Fiscal.Domain.{TaxCategories, VatRates}

  def validate(changeset) do
    changeset
    |> update_change(:tax_category, &TaxCategories.clean/1)
    |> update_change(:exemption_reason, &TaxCategories.clean/1)
    |> validate_inclusion(:tax_category, VatRates.categories())
    |> validate_length(:exemption_reason, max: TaxCategories.max_reason())
    |> reason_only_when_exempt()
  end

  defp reason_only_when_exempt(changeset) do
    case get_field(changeset, :tax_category) do
      "exempt" -> validate_required(changeset, [:exemption_reason])
      _other -> put_change(changeset, :exemption_reason, nil)
    end
  end
end
