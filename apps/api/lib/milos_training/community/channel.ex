defmodule MilosTraining.Community.Channel do
  @moduledoc "A channel inside a club (ADR-138)."

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(announcements wod challenges class_slot season custom)
  @write_policies ~w(staff members participants system_and_members)
  @memberships ~w(everyone opt_in invite)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_channels" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :kind, :string
    field :name, :string
    field :write_policy, :string
    field :membership, :string
    field :context_type, :string
    field :context_id, :binary_id
    field :position, :integer, default: 0
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(channel \\ %__MODULE__{}, attrs) do
    channel
    |> cast(attrs, [
      :organization_id,
      :club_id,
      :kind,
      :name,
      :write_policy,
      :membership,
      :context_type,
      :context_id,
      :position,
      :archived_at
    ])
    |> validate_required([:club_id, :kind, :write_policy, :membership])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:write_policy, @write_policies)
    |> validate_inclusion(:membership, @memberships)
    |> validate_length(:name, max: 60)
    |> check_constraint(:name, name: :community_channels_name_check)
    |> check_constraint(:context_id, name: :community_channels_context_check)
    |> unique_constraint(:kind, name: :community_channels_one_builtin_index)
    |> unique_constraint(:context_id, name: :community_channels_one_per_context_index)
  end

  def kinds, do: @kinds
end
