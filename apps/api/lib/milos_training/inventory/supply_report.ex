defmodule MilosTraining.Inventory.SupplyReport do
  @moduledoc "Someone flagged a consumable as running low: who, when, why (ADR-104)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inventory_supply_reports" do
    field :organization_id, :binary_id, read_after_writes: true
    field :supply_id, :binary_id
    field :user_id, :binary_id
    field :level, Ecto.Enum, values: [:running_low, :empty], default: :running_low
    field :seen_quantity, :integer
    field :place, :string
    field :note, :string
    field :reported_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :resolved_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :supply_id,
      :user_id,
      :level,
      :seen_quantity,
      :place,
      :note,
      :reported_at
    ])
    |> validate_required([:supply_id, :level, :reported_at])
    |> validate_number(:seen_quantity, greater_than_or_equal_to: 0)
    |> validate_length(:place, max: 120)
    |> validate_length(:note, max: 1000)
  end
end
