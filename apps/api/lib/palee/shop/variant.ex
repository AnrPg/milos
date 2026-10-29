defmodule Palee.Shop.Variant do
  @moduledoc """
  One sellable combination of a product's options (size × colour), with its
  SKU, price and optional compare-at and cost prices (ADR-190).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Fiscal.TaxCategoryChangeset
  alias Palee.Shop.Domain.StockStatus

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @tax_classes ~w(standard reduced super_reduced zero exempt)
  @editable [
    :title,
    :option_values,
    :sku,
    :barcode,
    :price_cents,
    :currency,
    :compare_at_price_cents,
    :cost_price_cents,
    :tax_class,
    :tax_category,
    :exemption_reason,
    :low_stock_threshold,
    :track_inventory,
    :position
  ]

  schema "shop_variants" do
    field :organization_id, :binary_id, read_after_writes: true
    field :product_id, :binary_id
    field :title, :string
    field :option_values, :map, default: %{}
    field :sku, :string
    field :barcode, :string
    field :price_cents, :integer
    field :currency, :string, default: "EUR"
    field :compare_at_price_cents, :integer
    field :cost_price_cents, :integer
    # Deprecated name of tax_category (ADR-244), kept in step with it.
    field :tax_class, :string
    # ADR-244: overrides the product's tax category (nil: as the product).
    field :tax_category, :string
    field :exemption_reason, :string
    field :low_stock_threshold, :integer
    field :track_inventory, :boolean, default: true
    field :stock_status, Ecto.Enum, values: StockStatus.statuses(), default: :out
    field :position, :integer, default: 0
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def editable, do: @editable
  def tax_classes, do: @tax_classes

  def changeset(variant \\ %__MODULE__{}, attrs) do
    variant
    |> cast(attrs, [:product_id, :stock_status, :archived_at | @editable])
    |> update_change(:sku, &blank_to_nil/1)
    |> update_change(:currency, &String.upcase/1)
    |> validate_required([:product_id, :price_cents, :currency])
    |> validate_length(:title, max: 160)
    |> validate_length(:sku, max: 64)
    |> validate_length(:barcode, max: 64)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:compare_at_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:cost_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:low_stock_threshold, greater_than_or_equal_to: 0)
    |> sync_tax_class()
    |> validate_inclusion(:tax_class, @tax_classes)
    |> TaxCategoryChangeset.validate()
    |> unique_constraint(:sku, name: :shop_variants_organization_sku_index)
    |> foreign_key_constraint(:product_id, name: :shop_variants_product_fkey)
  end

  # `tax_class` is the old name of `tax_category`: a client that still sends
  # it sets the category; a category outside the old five clears it.
  defp sync_tax_class(changeset) do
    case {fetch_change(changeset, :tax_category), fetch_change(changeset, :tax_class)} do
      {{:ok, category}, _class} ->
        put_change(changeset, :tax_class, if(category in @tax_classes, do: category))

      {:error, {:ok, class}} ->
        put_change(changeset, :tax_category, class)

      {:error, :error} ->
        changeset
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
