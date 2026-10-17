defmodule MilosTraining.Community.ClubMembership do
  @moduledoc """
  What a member chose about a club (ADR-138): the notification level, and for
  the club kinds that are not derived from a gym membership, the membership
  itself. A gym club's members are the gym's active members; this row only
  exists once they change a preference.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(member staff)
  @notify_levels ~w(all announcements none)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_club_memberships" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :user_id, :binary_id
    field :role, :string, default: "member"
    field :notify_level, :string, default: "all"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership \\ %__MODULE__{}, attrs) do
    membership
    |> cast(attrs, [:organization_id, :club_id, :user_id, :role, :notify_level])
    |> validate_required([:club_id, :user_id, :role, :notify_level])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:notify_level, @notify_levels)
  end

  def notify_levels, do: @notify_levels
end
