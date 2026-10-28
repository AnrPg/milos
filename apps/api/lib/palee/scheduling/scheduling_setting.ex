defmodule Palee.Scheduling.SchedulingSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "scheduling_settings" do
    field :organization_id, :binary_id
    field :default_capacity, :integer, default: 12
    field :default_auto_approve, :boolean, default: false
    field :default_booking_timeout_minutes, :integer, default: 60
    field :default_booking_window_days, :integer
    field :default_cancellation_cutoff_minutes, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [
      :organization_id,
      :default_capacity,
      :default_auto_approve,
      :default_booking_timeout_minutes,
      :default_booking_window_days,
      :default_cancellation_cutoff_minutes
    ])
    |> validate_required([
      :organization_id,
      :default_capacity,
      :default_auto_approve
    ])
    |> validate_number(:default_capacity, greater_than: 0, less_than_or_equal_to: 500)
    # ADR-222: nil = a request waits for approval until the class starts.
    |> validate_number(:default_booking_timeout_minutes,
      greater_than: 0,
      less_than_or_equal_to: 10_080
    )
    |> validate_number(:default_booking_window_days,
      greater_than: 0,
      less_than_or_equal_to: 365
    )
    |> validate_number(:default_cancellation_cutoff_minutes,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10_080
    )
  end
end
