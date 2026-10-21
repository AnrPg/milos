defmodule Palee.Inventory.SupplyMovement do
  @moduledoc "A restock, a use or a recount of a consumable (ADR-104)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inventory_supply_movements" do
    field :organization_id, :binary_id, read_after_writes: true
    field :supply_id, :binary_id
    field :user_id, :binary_id
    field :kind, Ecto.Enum, values: [:restock, :consume, :adjust]
    field :quantity, :integer
    field :unit_price_cents, :integer
    field :total_cents, :integer
    field :note, :string
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :supply_id,
      :user_id,
      :kind,
      :quantity,
      :unit_price_cents,
      :total_cents,
      :note,
      :occurred_at
    ])
    |> validate_required([:supply_id, :kind, :quantity, :occurred_at])
    |> validate_length(:note, max: 1000)
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:unit_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_cents, greater_than_or_equal_to: 0)
  end
end
