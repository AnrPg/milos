defmodule Palee.Inventory.MachinePlacement do
  @moduledoc "How many of a machine stand in one space (ADR-202), and where on its floor plan (ADR-290)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inventory_machine_placements" do
    field :organization_id, :binary_id, read_after_writes: true
    field :machine_id, :binary_id
    field :space_id, :binary_id
    field :quantity, :integer, default: 1
    # ADR-290: where on the space's floor plan each item stands, `[x, y]`
    # normalized (0..1), at most one per item.
    field :positions, {:array, {:array, :float}}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :machine_id, :space_id, :quantity, :positions])
    |> validate_required([:machine_id, :space_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:space_id, name: :inventory_machine_placements_space_fkey)
  end
end
