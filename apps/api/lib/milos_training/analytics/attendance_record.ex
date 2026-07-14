defmodule MilosTraining.Analytics.AttendanceRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "attendance_records" do
    field :scheduled_class_id, :binary_id
    field :booking_id, :binary_id
    field :user_id, :binary_id
    field :status, :string, default: "attended"
    field :marked_by_id, :binary_id
    field :marked_at, :utc_datetime_usec
    field :notes, :string
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record \\ %__MODULE__{}, params) do
    record
    |> cast(params, [
      :scheduled_class_id,
      :booking_id,
      :user_id,
      :status,
      :marked_by_id,
      :marked_at,
      :notes,
      :params
    ])
    |> validate_required([:scheduled_class_id, :user_id, :status, :marked_at])
    |> validate_inclusion(:status, ["attended", "missed", "cancelled", "late_cancel", "no_show"])
    |> unique_constraint([:scheduled_class_id, :user_id])
    |> foreign_key_constraint(:scheduled_class_id)
    |> foreign_key_constraint(:booking_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:marked_by_id)
  end
end
