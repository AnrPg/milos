defmodule Palee.Appointments.Booking do
  @moduledoc "A client booked into an appointment slot (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "appointment_bookings" do
    field :organization_id, :binary_id
    field :slot_id, :binary_id
    field :user_id, :binary_id
    field :status, :string, default: "booked"
    field :allowance, :string
    field :reservation_id, :binary_id
    field :booked_by_id, :binary_id
    field :late_cancellation, :boolean, default: false
    field :cancelled_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :id,
      :organization_id,
      :slot_id,
      :user_id,
      :allowance,
      :reservation_id,
      :booked_by_id
    ])
    |> validate_required([:organization_id, :slot_id, :user_id, :allowance])
    |> validate_inclusion(:allowance, ["pt_sessions", "assessments"])
    |> unique_constraint([:slot_id, :user_id], name: :appointment_bookings_slot_user_index)
  end

  def cancel_changeset(booking, late?, cancelled_at),
    do: change(booking, status: "cancelled", late_cancellation: late?, cancelled_at: cancelled_at)

  def attendance_changeset(booking, status) when status in ["attended", "no_show"],
    do: change(booking, status: status)
end
