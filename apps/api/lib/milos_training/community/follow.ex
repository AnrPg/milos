defmodule MilosTraining.Community.Follow do
  @moduledoc """
  One account following a person, a box or a club (ADR-142). The row belongs
  to the follower (`user_id`); a follow of a person starts as a request.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @target_types ~w(user organization club)
  @statuses ~w(requested active)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_follows" do
    field :user_id, :binary_id
    field :target_type, :string
    field :target_id, :binary_id
    field :status, :string
    field :accepted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def target_types, do: @target_types

  def changeset(follow \\ %__MODULE__{}, attrs) do
    follow
    |> cast(attrs, [:user_id, :target_type, :target_id, :status, :accepted_at])
    |> validate_required([:user_id, :target_type, :target_id, :status])
    |> validate_inclusion(:target_type, @target_types)
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:target_id, name: :community_follows_not_self)
    |> unique_constraint([:user_id, :target_type, :target_id])
  end
end
