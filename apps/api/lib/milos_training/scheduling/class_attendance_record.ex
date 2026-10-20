defmodule MilosTraining.Scheduling.ClassAttendanceRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "class_attendance_records" do
    field :organization_id, :binary_id
    field :scheduled_class_id, :binary_id
    field :booking_id, :binary_id
    field :user_id, :binary_id
    field :status, :string, default: "attended"
    field :marked_by_id, :binary_id
    field :marked_at, :utc_datetime_usec
    field :notes, :string
    field :params, :map, default: %{}
    # ADR-155: how a check-in happened; nil for roster marks by staff.
    field :check_in_method, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record \\ %__MODULE__{}, params) do
    record
    |> cast(params, [
      :organization_id,
      :scheduled_class_id,
      :booking_id,
      :user_id,
      :status,
      :marked_by_id,
      :marked_at,
      :notes,
      :params,
      :check_in_method
    ])
    |> validate_required([:organization_id, :scheduled_class_id, :user_id, :status, :marked_at])
    |> validate_inclusion(:status, ["attended", "missed", "cancelled", "late_cancel", "no_show"])
    |> validate_inclusion(:check_in_method, ~w(door_qr member_qr wallet desk_search self))
    |> unique_constraint([:scheduled_class_id, :user_id])
    |> foreign_key_constraint(:scheduled_class_id)
    |> foreign_key_constraint(:booking_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:marked_by_id)
  end
end
