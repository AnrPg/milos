defmodule MilosTraining.Facility.CheckIn do
  @moduledoc "An open-gym visit: one per member and day (ADR-097)."

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

    timestamps(type: :utc_datetime_usec)
  end

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
      :reservation_id
    ])
    |> validate_required([:organization_id, :user_id, :checked_in_on, :checked_in_at, :source])
    |> validate_inclusion(:source, ["self", "staff"])
    |> foreign_key_constraint(:location_id)
    |> unique_constraint([:user_id, :checked_in_on], name: :facility_check_ins_daily_index)
  end
end
