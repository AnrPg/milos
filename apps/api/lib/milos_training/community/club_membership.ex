defmodule MilosTraining.Community.ClubMembership do
  @moduledoc """
  What a member chose about a club (ADR-138): the notification level, and for
  the club kinds that are not derived from a gym membership, the membership
  itself. A gym club's members are the gym's active members; this row only
  exists once they change a preference. An open club's members are these
  rows (ADR-143); `pending` waits for staff when the club asks for approval.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(member staff)
  @notify_levels ~w(all announcements none)
  @statuses ~w(active pending)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_club_memberships" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :user_id, :binary_id
    field :role, :string, default: "member"
    field :notify_level, :string, default: "all"
    field :status, :string, default: "active"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership \\ %__MODULE__{}, attrs) do
    membership
    |> cast(attrs, [:organization_id, :club_id, :user_id, :role, :notify_level, :status])
    |> validate_required([:club_id, :user_id, :role, :notify_level])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:notify_level, @notify_levels)
    |> validate_inclusion(:status, @statuses)
  end

  def notify_levels, do: @notify_levels
end
