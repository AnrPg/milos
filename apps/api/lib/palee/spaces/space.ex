defmodule Palee.Spaces.Space do
  @moduledoc """
  A room or area of a branch (ADR-202): where classes take place and what
  the cleaning staff clean. The cleaning areas of ADR-102 became spaces, so a
  space keeps its cleaning task checklist.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Spaces.Domain.SpacePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @fields [
    :organization_id,
    :name,
    :description,
    :directions,
    :location_id,
    :tasks,
    :floor_plan_id,
    :area,
    :archived_at
  ]

  schema "spaces" do
    field :organization_id, :binary_id, read_after_writes: true
    field :name, :string
    field :description, :string
    field :directions, :string
    field :location_id, :binary_id
    field :tasks, {:array, :string}, default: []
    field :floor_plan_id, :binary_id
    field :area, :map
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(space \\ %__MODULE__{}, attrs) do
    space
    |> cast(attrs, @fields)
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> update_change(:directions, &blank_to_nil/1)
    |> update_change(:tasks, fn tasks ->
      tasks |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
    end)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:description, max: 2_000)
    |> validate_length(:directions, max: 2_000)
    |> validate_length(:tasks, max: 30)
    |> validate_area()
    |> foreign_key_constraint(:floor_plan_id, name: :spaces_floor_plan_fkey)
  end

  defp validate_area(changeset) do
    case fetch_change(changeset, :area) do
      {:ok, area} ->
        case SpacePolicy.normalize_area(area) do
          {:ok, area} -> put_change(changeset, :area, area)
          {:error, _reason} -> add_error(changeset, :area, "must be 3 to 32 points within 0..1")
        end

      :error ->
        changeset
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
