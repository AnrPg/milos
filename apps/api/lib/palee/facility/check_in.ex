defmodule Palee.Facility.CheckIn do
  @moduledoc """
  An open-gym visit: one per member and day (ADR-097), with how it happened
  (ADR-155): `door_qr`, `door_poster`, `member_qr`, `wallet`, `desk_search`,
  `imported` (a visit brought in by a CSV import, ADR-254)
  or `self`, and `door_nfc` or `geofence` (ADR-173).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "facility_check_ins" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :location_id, :binary_id
    field :checked_in_on, :date
    field :checked_in_at, :utc_datetime_usec
    field :source, :string
    field :recorded_by_id, :binary_id
    field :reservation_id, :binary_id
    field :method, :string, default: "self"

    timestamps(type: :utc_datetime_usec)
  end

  @methods ~w(door_qr door_poster door_nfc geofence member_qr wallet desk_search self imported)

  @doc "How a check-in happened (ADR-155)."
  def methods, do: @methods

  def changeset(check_in \\ %__MODULE__{}, params) do
    check_in
    |> cast(params, [
      :id,
      :organization_id,
      :user_id,
      :location_id,
      :checked_in_on,
      :checked_in_at,
      :source,
      :recorded_by_id,
      :reservation_id,
      :method
    ])
    |> validate_required([:organization_id, :user_id, :checked_in_on, :checked_in_at, :source])
    |> validate_inclusion(:source, ["self", "staff"])
    |> validate_inclusion(:method, methods())
    |> foreign_key_constraint(:location_id)
    |> unique_constraint([:user_id, :checked_in_on], name: :facility_check_ins_daily_index)
  end
end
