defmodule Palee.Spaces.FloorPlan do
  @moduledoc "One floor of a branch as an image (a ready `floor_plan` upload, ADR-202)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "space_floor_plans" do
    field :organization_id, :binary_id, read_after_writes: true
    field :location_id, :binary_id
    field :name, :string
    field :media_id, :binary_id
    field :sort_order, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :location_id, :name, :media_id, :sort_order])
    |> validate()
    |> validate_required([:media_id])
  end

  def update_changeset(plan, attrs) do
    plan
    |> cast(attrs, [:name, :media_id, :sort_order])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0, less_than: 1_000)
  end
end
