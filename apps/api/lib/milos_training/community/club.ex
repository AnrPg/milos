defmodule MilosTraining.Community.Club do
  @moduledoc "A club: a gym's own club first, other kinds in Phase 2 (ADR-138)."

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(gym open member_group pt_squad season)
  @join_policies ~w(members_only open approval invite)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_clubs" do
    field :organization_id, :binary_id, read_after_writes: true
    field :kind, :string
    field :name, :string
    field :join_policy, :string, default: "members_only"
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(club \\ %__MODULE__{}, attrs) do
    club
    |> cast(attrs, [:organization_id, :kind, :name, :join_policy, :archived_at])
    |> validate_required([:kind, :join_policy])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:join_policy, @join_policies)
    |> validate_length(:name, max: 80)
    |> check_constraint(:name, name: :community_clubs_name_check)
    |> unique_constraint(:organization_id, name: :community_clubs_one_gym_club_index)
  end

  def kinds, do: @kinds
end
