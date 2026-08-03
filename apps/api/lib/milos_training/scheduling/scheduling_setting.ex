defmodule MilosTraining.Scheduling.SchedulingSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "scheduling_settings" do
    field :organization_id, :binary_id
    field :default_capacity, :integer, default: 12
    field :default_auto_approve, :boolean, default: false
    field :default_booking_timeout_minutes, :integer, default: 60
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [
      :default_capacity,
      :default_auto_approve,
      :default_booking_timeout_minutes
    ])
    |> validate_required([
      :default_capacity,
      :default_auto_approve,
      :default_booking_timeout_minutes
    ])
    |> validate_number(:default_capacity, greater_than: 0, less_than_or_equal_to: 500)
    |> validate_number(:default_booking_timeout_minutes,
      greater_than: 0,
      less_than_or_equal_to: 10_080
    )
  end
end
