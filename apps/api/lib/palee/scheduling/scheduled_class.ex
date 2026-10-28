defmodule Palee.Scheduling.ScheduledClass do
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Scheduling.{Booking, ClassSeries, ClassType}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "scheduled_classes" do
    field :organization_id, :binary_id
    field :master_workout_id, :binary_id
    # ADR-224: the day WOD rule the WOD came from; nil with a WOD = its own.
    # Never cast from requests: only day-WOD inheritance writes it.
    field :day_workout_id, :binary_id
    field :name, :string, default: "Class"
    field :duration_minutes, :integer, default: 60
    field :scheduled_at, :utc_datetime
    field :capacity, :integer
    field :auto_approve, :boolean, default: false
    field :booking_timeout_minutes, :integer, default: 60
    # ADR-097: optional Facility location.
    field :location_id, :binary_id
    # ADR-202: optional space (room) of the branch.
    field :space_id, :binary_id
    # The coach who runs it (ADR-100).
    field :coach_user_id, :binary_id
    # ADR-200 §2: paused = no new bookings; cancelled = it will not happen.
    field :paused_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :cancel_reason, :string

    belongs_to :class_type, ClassType
    belongs_to :class_series, ClassSeries

    has_many :bookings, Booking, preload_order: [asc: :inserted_at]

    timestamps()
  end

  def changeset(slot \\ %__MODULE__{}, params) do
    slot
    |> cast(params, [
      :organization_id,
      :master_workout_id,
      :class_type_id,
      :location_id,
      :space_id,
      :coach_user_id,
      :class_series_id,
      :name,
      :duration_minutes,
      :scheduled_at,
      :capacity,
      :auto_approve,
      :booking_timeout_minutes
    ])
    |> validate_required([
      :organization_id,
      :class_type_id,
      :name,
      :duration_minutes,
      :scheduled_at,
      :capacity,
      :auto_approve,
      :booking_timeout_minutes
    ])
    # ADR-176: the WOD is optional; a standalone class without one is a draft.
    |> detach_from_day_workout()
    |> validate_number(:capacity, greater_than: 0)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 1440)
    |> validate_number(:booking_timeout_minutes, greater_than: 0)
    |> validate_future_schedule()
    |> foreign_key_constraint(:master_workout_id)
    |> foreign_key_constraint(:class_type_id)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:space_id, name: :scheduled_classes_space_fkey)
    |> foreign_key_constraint(:class_series_id)
  end

  # ADR-224: choosing a WOD for the class itself overrides the day's WOD.
  defp detach_from_day_workout(changeset) do
    if changed?(changeset, :master_workout_id),
      do: put_change(changeset, :day_workout_id, nil),
      else: changeset
  end

  @doc "Pausing, cancelling and their undo (ADR-200 §2); nothing else changes."
  def state_changeset(slot, params) do
    slot
    |> cast(params, [:paused_at, :cancelled_at, :cancel_reason])
    |> update_change(:cancel_reason, &blank_to_nil/1)
    |> validate_length(:cancel_reason, max: 280)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp validate_future_schedule(changeset) do
    case get_change(changeset, :scheduled_at) do
      nil ->
        changeset

      %DateTime{} = scheduled_at ->
        if DateTime.compare(scheduled_at, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, :scheduled_at, "must be in the future")
        end

      _ ->
        changeset
    end
  end
end
