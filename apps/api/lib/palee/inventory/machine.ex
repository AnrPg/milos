defmodule Palee.Inventory.Machine do
  @moduledoc "A training machine or appliance the gym owns (ADR-104)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Inventory.Domain.MachinePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @fields [
    :organization_id,
    :name,
    :category,
    :brand,
    :model,
    :serial_number,
    :location_id,
    :quantity,
    :purchased_on,
    :purchase_price_cents,
    :warranty_until,
    :service_contact,
    :service_interval_days,
    :last_serviced_on,
    :status,
    :notes,
    :archived_at
  ]

  schema "inventory_machines" do
    field :organization_id, :binary_id, read_after_writes: true
    field :name, :string
    field :category, Ecto.Enum, values: MachinePolicy.categories(), default: :training
    field :brand, :string
    field :model, :string
    field :serial_number, :string
    field :location_id, :binary_id
    field :quantity, :integer, default: 1
    field :purchased_on, :date
    field :purchase_price_cents, :integer
    field :warranty_until, :date
    field :service_contact, :string
    field :service_interval_days, :integer
    field :last_serviced_on, :date
    field :status, Ecto.Enum, values: MachinePolicy.statuses(), default: :working
    field :notes, :string
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def fields, do: @fields

  def changeset(machine \\ %__MODULE__{}, attrs) do
    machine
    |> cast(attrs, @fields)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :category, :status])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:brand, max: 120)
    |> validate_length(:model, max: 120)
    |> validate_length(:serial_number, max: 120)
    |> validate_length(:service_contact, max: 1000)
    |> validate_length(:notes, max: 4000)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:purchase_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:service_interval_days, greater_than: 0)
  end
end
