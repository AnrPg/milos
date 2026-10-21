defmodule MilosTraining.Community.ChannelMembership do
  @moduledoc """
  A member and an opt-in or invite-only channel (ADR-138). `opt_in`,
  `invited` and `auto` rows are members; `suggested` is an offer (D7: a
  frequent booker of a class) and `dismissed` remembers that they left or
  declined, so they are not offered it again. In a member group (ADR-143)
  `requested` waits for one of its admins, and `role` marks those admins.
  In a PT squad (ADR-168) `pending_invite` is the coach's invitation, a
  member only once the client accepts it (`invited`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(opt_in suggested invited auto dismissed requested pending_invite)
  @roles ~w(member admin)
  @member_sources ~w(opt_in invited auto)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_channel_memberships" do
    field :organization_id, :binary_id, read_after_writes: true
    field :channel_id, :binary_id
    field :user_id, :binary_id
    field :source, :string
    field :role, :string, default: "member"

    timestamps(type: :utc_datetime_usec)
  end

  def member_sources, do: @member_sources

  def changeset(membership \\ %__MODULE__{}, attrs) do
    membership
    |> cast(attrs, [:organization_id, :channel_id, :user_id, :source, :role])
    |> validate_required([:channel_id, :user_id, :source])
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:role, @roles)
  end
end
