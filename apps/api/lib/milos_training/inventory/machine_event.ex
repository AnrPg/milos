defmodule MilosTraining.Inventory.MachineEvent do
  @moduledoc "One line of a machine's log: a note, an issue, a repair, a service (ADR-104)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Inventory.Domain.MachinePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inventory_machine_events" do
    field :organization_id, :binary_id, read_after_writes: true
    field :machine_id, :binary_id
    field :user_id, :binary_id
    field :kind, Ecto.Enum, values: MachinePolicy.kinds()
    field :severity, Ecto.Enum, values: MachinePolicy.severities()
    field :symptom, Ecto.Enum, values: MachinePolicy.symptoms()
    field :usable, :boolean
    field :body, :string
    field :cost_cents, :integer
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :machine_id,
      :user_id,
      :kind,
      :severity,
      :symptom,
      :usable,
      :body,
      :cost_cents,
      :occurred_at
    ])
    |> validate_required([:machine_id, :kind, :occurred_at])
    |> validate_length(:body, max: 4000)
    |> validate_number(:cost_cents, greater_than_or_equal_to: 0)
  end
end
