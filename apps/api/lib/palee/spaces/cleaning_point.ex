defmodule Palee.Spaces.CleaningPoint do
  @moduledoc """
  One point of a room's visual cleaning checklist (ADR-290): a photo of a
  part of the room and what must be cleaned there. The janitor answers each
  point «Καθαρό» or «Δεν καθαρίστηκε» when finishing a cleaning.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "space_cleaning_points" do
    field :organization_id, :binary_id, read_after_writes: true
    field :space_id, :binary_id
    field :media_id, :binary_id
    field :instruction, :string
    field :sort_order, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :space_id, :media_id, :instruction, :sort_order])
    |> validate_required([:space_id, :media_id])
    |> validate()
    |> unique_constraint(:media_id)
  end

  def update_changeset(point, attrs) do
    point
    |> cast(attrs, [:media_id, :instruction, :sort_order])
    |> validate()
    |> unique_constraint(:media_id)
  end

  defp validate(changeset) do
    changeset
    |> update_change(:instruction, &Palee.Spaces.Domain.SpacePolicy.blank_to_nil/1)
    |> validate_required([:instruction])
    |> validate_length(:instruction, max: 500)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0, less_than: 1_000)
  end
end
