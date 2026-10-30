defmodule Palee.Spaces.Photo do
  @moduledoc """
  A photo of a room (ADR-290), to get an idea of it. Shown on the public box
  page only when its uploader turns `public` on.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "space_photos" do
    field :organization_id, :binary_id, read_after_writes: true
    field :space_id, :binary_id
    field :media_id, :binary_id
    field :caption, :string
    field :public, :boolean, default: false
    field :sort_order, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :space_id, :media_id, :caption, :public, :sort_order])
    |> validate_required([:space_id, :media_id])
    |> validate()
    |> unique_constraint(:media_id)
  end

  def update_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:caption, :public, :sort_order])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> update_change(:caption, &Palee.Spaces.Domain.SpacePolicy.blank_to_nil/1)
    |> validate_length(:caption, max: 200)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0, less_than: 1_000)
  end
end
