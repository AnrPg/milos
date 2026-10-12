defmodule MilosTraining.Inventory.Supply do
  @moduledoc "A consumable the gym keeps in stock, and where to buy it (ADR-104)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Inventory.Domain.StockPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @editable [
    :name,
    :description,
    :brand,
    :shop,
    :url,
    :unit,
    :unit_price_cents,
    :consumption_speed,
    :reorder_level
  ]

  schema "inventory_supplies" do
    field :organization_id, :binary_id, read_after_writes: true
    field :name, :string
    field :description, :string
    field :brand, :string
    field :shop, :string
    field :url, :string
    field :unit, :string
    field :unit_price_cents, :integer
    field :quantity, :integer, default: 0
    field :consumption_speed, Ecto.Enum, values: StockPolicy.speeds(), default: :regular
    field :reorder_level, :integer
    field :stock_status, Ecto.Enum, values: [:ok, :low, :critical, :out], default: :ok
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def editable, do: @editable

  def changeset(supply \\ %__MODULE__{}, attrs) do
    supply
    |> cast(attrs, [:organization_id, :quantity, :stock_status, :archived_at | @editable])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :consumption_speed])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:description, max: 2000)
    |> validate_length(:brand, max: 120)
    |> validate_length(:shop, max: 200)
    |> validate_length(:url, max: 2048)
    |> validate_format(:url, ~r{^https?://}i)
    |> validate_length(:unit, max: 40)
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:unit_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:reorder_level, greater_than_or_equal_to: 0)
  end
end
