defmodule MilosTraining.Community.Club do
  @moduledoc """
  A club (ADR-138): every gym has its own; an `open` club is one staff run
  for anyone, members of the gym or not (ADR-143).
  """

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
    field :description, :string
    field :cover_media_id, :binary_id
    field :created_by_id, :binary_id
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(club \\ %__MODULE__{}, attrs) do
    club
    |> cast(attrs, [
      :organization_id,
      :kind,
      :name,
      :join_policy,
      :description,
      :cover_media_id,
      :created_by_id,
      :archived_at
    ])
    |> update_change(:name, &trim/1)
    |> update_change(:description, &trim/1)
    |> validate_required([:kind, :join_policy])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:join_policy, @join_policies)
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 1_000)
    |> check_constraint(:description, name: :community_clubs_description_check)
    |> check_constraint(:name, name: :community_clubs_name_check)
    |> unique_constraint(:organization_id, name: :community_clubs_one_gym_club_index)
  end

  def kinds, do: @kinds

  defp trim(nil), do: nil
  defp trim(value), do: value |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))
end
