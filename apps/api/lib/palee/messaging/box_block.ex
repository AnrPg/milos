defmodule Palee.Messaging.BoxBlock do
  @moduledoc "ADR-282: someone a box no longer hears from (they cannot write to it)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_box_blocks" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :blocked_by_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @type t :: %__MODULE__{}

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:organization_id, :user_id, :blocked_by_id])
    |> validate_required([:organization_id, :user_id])
    |> unique_constraint([:organization_id, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
