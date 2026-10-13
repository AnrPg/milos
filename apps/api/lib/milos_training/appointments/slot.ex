defmodule MilosTraining.Appointments.Slot do
  @moduledoc "A bookable PT session or assessment published by a coach (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "appointment_slots" do
    field :organization_id, :binary_id
    field :coach_id, :binary_id
    field :kind, :string
    field :format, :string
    field :starts_at, :utc_datetime_usec
    field :duration_minutes, :integer
    field :capacity, :integer, default: 1
    field :location_id, :binary_id
    field :notes, :string
    field :cancelled_at, :utc_datetime_usec
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :organization_id,
      :coach_id,
      :kind,
      :format,
      :starts_at,
      :duration_minutes,
      :capacity,
      :location_id,
      :notes,
      :created_by_id
    ])
    |> validate_required([
      :organization_id,
      :coach_id,
      :kind,
      :format,
      :starts_at,
      :duration_minutes
    ])
    |> validate_inclusion(:kind, ["pt_session", "assessment"])
    |> validate_inclusion(:format, ["one_to_one", "semi_private"])
    |> validate_number(:duration_minutes,
      greater_than_or_equal_to: 15,
      less_than_or_equal_to: 240
    )
    |> validate_capacity()
    |> validate_length(:notes, max: 1000)
    |> foreign_key_constraint(:location_id)
    |> check_constraint(:capacity, name: :appointment_slots_format)
  end

  def cancel_changeset(slot, cancelled_at), do: change(slot, cancelled_at: cancelled_at)

  defp validate_capacity(changeset) do
    case get_field(changeset, :format) do
      "one_to_one" ->
        put_change(changeset, :capacity, 1)

      "semi_private" ->
        validate_number(changeset, :capacity,
          greater_than_or_equal_to: 2,
          less_than_or_equal_to: 4
        )

      _other ->
        changeset
    end
  end
end
