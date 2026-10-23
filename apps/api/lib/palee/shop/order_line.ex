defmodule Palee.Shop.OrderLine do
  @moduledoc """
  One line of a shop order, with snapshots of what was sold (title, SKU,
  price, cost, tax class) so later catalog edits never rewrite history. Its
  id is the `source_id` of the Finance invoice line it produced (ADR-190).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shop_order_lines" do
    field :organization_id, :binary_id, read_after_writes: true
    field :order_id, :binary_id
    field :product_id, :binary_id
    field :variant_id, :binary_id
    field :product_title, :string
    field :variant_title, :string
    field :sku, :string
    field :quantity, :integer
    field :unit_price_cents, :integer
    field :cost_price_cents, :integer
    field :tax_class, :string
    field :discount_cents, :integer, default: 0
    field :total_cents, :integer
    field :refunded_quantity, :integer, default: 0
    field :refunded_cents, :integer, default: 0
    field :location_id, :binary_id
    field :finance_invoice_line_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :order_id,
      :product_id,
      :variant_id,
      :product_title,
      :variant_title,
      :sku,
      :quantity,
      :unit_price_cents,
      :cost_price_cents,
      :tax_class,
      :discount_cents,
      :total_cents,
      :location_id
    ])
    |> validate_required([
      :order_id,
      :product_id,
      :variant_id,
      :product_title,
      :quantity,
      :unit_price_cents,
      :total_cents
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> check_constraint(:quantity, name: :shop_order_lines_amounts_check)
  end

  def update_changeset(line, attrs) do
    line
    |> cast(attrs, [:refunded_quantity, :refunded_cents, :finance_invoice_line_id])
    |> check_constraint(:refunded_quantity, name: :shop_order_lines_amounts_check)
  end
end
