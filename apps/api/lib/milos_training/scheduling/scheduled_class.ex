defmodule MilosTraining.Scheduling.ScheduledClass do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Scheduling.{Booking, ClassType}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "scheduled_classes" do
    field :master_workout_id, :binary_id
    field :scheduled_at, :utc_datetime
    field :capacity, :integer
    field :auto_approve, :boolean, default: false
    field :booking_timeout_minutes, :integer, default: 60

    belongs_to :class_type, ClassType

    has_many :bookings, Booking, preload_order: [asc: :inserted_at]

    timestamps()
  end

  def changeset(slot \\ %__MODULE__{}, params) do
    slot
    |> cast(params, [
      :master_workout_id,
      :class_type_id,
      :scheduled_at,
      :capacity,
      :auto_approve,
      :booking_timeout_minutes
    ])
    |> validate_required([
      :master_workout_id,
      :class_type_id,
      :scheduled_at,
      :capacity,
      :auto_approve,
      :booking_timeout_minutes
    ])
    |> validate_number(:capacity, greater_than: 0)
    |> validate_number(:booking_timeout_minutes, greater_than: 0)
    |> validate_future_schedule()
    |> foreign_key_constraint(:master_workout_id)
    |> foreign_key_constraint(:class_type_id)
  end

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
