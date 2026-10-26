defmodule Palee.Spaces.Unavailability do
  @moduledoc "A time when a space cannot hold classes, with its reason (ADR-202)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "space_unavailabilities" do
    field :organization_id, :binary_id, read_after_writes: true
    field :space_id, :binary_id
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :reason, :string
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :space_id, :starts_at, :ends_at, :reason, :created_by_id])
    |> update_change(:reason, &String.trim/1)
    |> validate_required([:space_id, :starts_at, :ends_at])
    |> validate_length(:reason, max: 500)
    |> check_constraint(:ends_at, name: :space_unavailabilities_order_check)
  end
end
