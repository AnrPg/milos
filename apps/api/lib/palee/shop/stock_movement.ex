defmodule Palee.Shop.StockMovement do
  @moduledoc """
  One row of the append-only stock ledger (ADR-190): a receipt, a sale, a
  restock after a refund, an adjustment with its reason, one side of a
  transfer, or a reservation and its release. `quantity` is signed for
  on-hand changes; reserve and release are positive counts of reserved stock.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Shop.Domain.StockLedger

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shop_stock_movements" do
    field :organization_id, :binary_id, read_after_writes: true
    field :variant_id, :binary_id
    field :location_id, :binary_id
    field :kind, Ecto.Enum, values: StockLedger.kinds()
    field :quantity, :integer
    field :reason, Ecto.Enum, values: StockLedger.adjustment_reasons()
    field :note, :string
    field :unit_cost_cents, :integer
    field :order_id, :binary_id
    field :order_line_id, :binary_id
    field :transfer_id, :binary_id
    field :user_id, :binary_id
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :variant_id,
      :location_id,
      :kind,
      :quantity,
      :reason,
      :note,
      :unit_cost_cents,
      :order_id,
      :order_line_id,
      :transfer_id,
      :user_id,
      :occurred_at
    ])
    |> validate_required([:variant_id, :kind, :quantity, :occurred_at])
    |> validate_length(:note, max: 1000)
    |> validate_number(:unit_cost_cents, greater_than_or_equal_to: 0)
    |> check_constraint(:quantity, name: :shop_stock_movements_sign_check)
    |> check_constraint(:reason, name: :shop_stock_movements_reason_check)
  end
end
