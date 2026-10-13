defmodule MilosTraining.Facility.Location do
  @moduledoc "A gym location of an organization (ADR-097)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "facility_locations" do
    field :organization_id, :binary_id
    field :name, :string
    field :address, :string
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(location \\ %__MODULE__{}, params) do
    location
    |> cast(params, [:organization_id, :name, :address])
    |> validate_required([:organization_id])
    |> validate_fields()
  end

  def update_changeset(location, params) do
    location
    |> cast(params, [:name, :address])
    |> validate_fields()
  end

  def archive_changeset(location, archived_at), do: change(location, archived_at: archived_at)

  defp validate_fields(changeset) do
    changeset
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_length(:address, max: 300)
    |> unique_constraint(:name, name: :facility_locations_organization_name_index)
  end
end
