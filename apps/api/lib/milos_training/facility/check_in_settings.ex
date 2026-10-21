defmodule MilosTraining.Facility.CheckInSettings do
  @moduledoc """
  The owner's «Ρυθμίσεις › Check-in» for one box (ADR-155). A box without a
  row has `CheckInRules.defaults/0`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Facility.Domain.CheckInRules

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "facility_check_in_settings" do
    field :organization_id, :binary_id
    field :window_before_minutes, :integer, default: 30
    field :window_after_minutes, :integer, default: 15
    field :open_gym_requires_package, :boolean, default: true
    field :visitor_trial_offer, :boolean, default: true
    field :desk_override, :boolean, default: false
    field :door_rotation_seconds, :integer, default: 30
    field :member_code_mode, :string, default: "rotating"
    field :geofence_reminder, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:organization_id | CheckInRules.fields()])
    |> validate_required([:organization_id | CheckInRules.fields()])
    |> validate_number(:window_before_minutes,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 120
    )
    |> validate_number(:window_after_minutes,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 120
    )
    |> validate_inclusion(:door_rotation_seconds, CheckInRules.rotations())
    |> validate_inclusion(:member_code_mode, CheckInRules.member_code_modes())
    |> unique_constraint(:organization_id)
  end
end
