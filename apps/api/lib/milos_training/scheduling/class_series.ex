defmodule MilosTraining.Scheduling.ClassSeries do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Scheduling.{ClassType, ScheduledClass}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "class_series" do
    field :organization_id, :binary_id
    field :master_workout_id, :binary_id
    field :name, :string
    field :duration_minutes, :integer
    field :timezone, :string, default: "Etc/UTC"
    field :starts_on, :date
    field :ends_on, :date
    field :local_start_time, :time
    field :weekdays, {:array, :integer}, default: []
    field :excluded_dates, {:array, :date}, default: []
    field :materialized_through, :date
    field :capacity, :integer
    field :auto_approve, :boolean, default: false
    field :booking_timeout_minutes, :integer, default: 60
    field :status, :string, default: "active"

    belongs_to :class_type, ClassType
    has_many :occurrences, ScheduledClass

    timestamps()
  end

  def changeset(series \\ %__MODULE__{}, params) do
    series
    |> cast(params, [
      :organization_id,
      :master_workout_id,
      :class_type_id,
      :name,
      :duration_minutes,
      :timezone,
      :starts_on,
      :ends_on,
      :local_start_time,
      :weekdays,
      :excluded_dates,
      :materialized_through,
      :capacity,
      :auto_approve,
      :booking_timeout_minutes,
      :status
    ])
    |> validate_required([
      :organization_id,
      :class_type_id,
      :name,
      :duration_minutes,
      :timezone,
      :starts_on,
      :local_start_time,
      :weekdays,
      :materialized_through,
      :capacity,
      :auto_approve,
      :booking_timeout_minutes,
      :status
    ])
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:timezone, min: 1, max: 100)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 1440)
    |> validate_number(:capacity, greater_than: 0)
    |> validate_number(:booking_timeout_minutes, greater_than: 0)
    |> validate_length(:weekdays, min: 1, max: 7)
    |> validate_subset(:weekdays, Enum.to_list(1..7))
    |> validate_inclusion(:status, ["active", "ended", "cancelled"])
    |> validate_date_order()
    |> foreign_key_constraint(:master_workout_id)
    |> foreign_key_constraint(:class_type_id)
  end

  defp validate_date_order(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.before?(ends_on, starts_on) do
      add_error(changeset, :ends_on, "must be on or after the start date")
    else
      changeset
    end
  end
end
