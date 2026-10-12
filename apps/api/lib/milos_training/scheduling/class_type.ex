defmodule MilosTraining.Scheduling.ClassType do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "class_types" do
    field :organization_id, :binary_id
    field :name, :string
    field :slug, :string
    field :sort_order, :integer, default: 0
    field :archived_at, :utc_datetime
    field :credit_cost, :integer, default: 1
    field :kind, :string, default: "class"

    timestamps(type: :utc_datetime)
  end

  def create_changeset(class_type \\ %__MODULE__{}, params) do
    class_type
    |> cast(params, [:organization_id, :name, :slug, :sort_order, :credit_cost, :kind])
    |> validate_required([:organization_id, :name, :slug, :sort_order])
    |> validate_phase_b()
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
    |> unique_constraint([:organization_id, :slug], name: :class_types_organization_slug_index)
  end

  def update_changeset(class_type, params) do
    class_type
    |> cast(params, [:name, :sort_order, :credit_cost, :kind])
    |> validate_required([:name, :sort_order])
    |> validate_phase_b()
    |> validate_length(:name, min: 2, max: 80)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
  end

  # ADR-097: credit weighting and event classes.
  defp validate_phase_b(changeset) do
    changeset
    |> validate_number(:credit_cost, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_inclusion(:kind, ["class", "event"])
  end

  def archive_changeset(class_type, archived_at) do
    change(class_type, archived_at: archived_at)
  end
end
