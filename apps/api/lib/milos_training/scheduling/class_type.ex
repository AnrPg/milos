defmodule MilosTraining.Scheduling.ClassType do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "class_types" do
    field :name, :string
    field :slug, :string
    field :sort_order, :integer, default: 0
    field :archived_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def create_changeset(class_type \\ %__MODULE__{}, params) do
    class_type
    |> cast(params, [:name, :slug, :sort_order])
    |> validate_required([:name, :slug, :sort_order])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
    |> unique_constraint(:slug)
  end

  def update_changeset(class_type, params) do
    class_type
    |> cast(params, [:name, :sort_order])
    |> validate_required([:name, :sort_order])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
  end

  def archive_changeset(class_type, archived_at) do
    change(class_type, archived_at: archived_at)
  end
end
