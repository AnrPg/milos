defmodule Palee.Shop.StockLevel do
  @moduledoc """
  The cached projection of the stock ledger for one variant at one branch
  (no branch = the business's single stock): on hand and reserved by open
  orders. Only the ledger writer changes it, in the same transaction as the
  movement and under a row lock (ADR-190).
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shop_stock_levels" do
    field :organization_id, :binary_id, read_after_writes: true
    field :variant_id, :binary_id
    field :location_id, :binary_id
    field :on_hand, :integer, default: 0
    field :reserved, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end
end
