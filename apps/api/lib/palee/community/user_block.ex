defmodule Palee.Community.UserBlock do
  @moduledoc """
  A person someone blocked (ADR-169 §5): the two never meet in Partners
  again, their matches and buddy links end. Personal, owner-only.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "community_user_blocks" do
    field :user_id, :binary_id
    field :blocked_user_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :blocked_user_id])
    |> validate_required([:user_id, :blocked_user_id])
    |> check_constraint(:blocked_user_id, name: :community_user_blocks_pair_check)
    |> unique_constraint([:user_id, :blocked_user_id])
  end
end
