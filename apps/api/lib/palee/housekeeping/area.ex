defmodule Palee.Housekeeping.Area do
  @moduledoc "A place that is cleaned, with its task checklist (ADR-102)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "housekeeping_areas" do
    field :organization_id, :binary_id, read_after_writes: true
    field :name, :string
    field :location_id, :binary_id
    field :tasks, {:array, :string}, default: []
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(area \\ %__MODULE__{}, attrs) do
    area
    |> cast(attrs, [:organization_id, :name, :location_id, :tasks, :archived_at])
    |> update_change(:name, &String.trim/1)
    |> update_change(:tasks, fn tasks ->
      tasks |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
    end)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:tasks, max: 30)
  end
end
