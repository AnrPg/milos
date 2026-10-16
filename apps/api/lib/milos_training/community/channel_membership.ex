defmodule MilosTraining.Community.ChannelMembership do
  @moduledoc "A member in an opt-in or invite-only channel (ADR-138)."

  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(opt_in suggested invited auto)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_channel_memberships" do
    field :organization_id, :binary_id, read_after_writes: true
    field :channel_id, :binary_id
    field :user_id, :binary_id
    field :source, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership \\ %__MODULE__{}, attrs) do
    membership
    |> cast(attrs, [:organization_id, :channel_id, :user_id, :source])
    |> validate_required([:channel_id, :user_id, :source])
    |> validate_inclusion(:source, @sources)
  end
end
