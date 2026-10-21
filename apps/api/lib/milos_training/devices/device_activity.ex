defmodule MilosTraining.Devices.DeviceActivity do
  @moduledoc """
  A workout from a watch (ADR-161): its own journal entry (`own`), the
  watch's numbers on an entry the member logged (`merged`), or waiting for
  the member to say which class it was (`pending`, with its `candidates`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Devices.Domain.Catalog

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "device_activities" do
    field :user_id, :binary_id
    field :organization_id, :binary_id
    field :provider, :string
    field :provider_activity_id, :string
    field :state, :string, default: "own"
    field :sport, :string
    field :activity_type, :string
    field :title, :string
    field :started_at, :utc_datetime_usec
    field :started_tz, :string, default: "UTC"
    field :duration_seconds, :integer
    field :distance_meters, :float
    field :avg_heart_rate, :integer
    field :max_heart_rate, :integer
    field :calories, :integer
    field :class_id, :binary_id
    field :merged_kind, :string
    field :merged_id, :binary_id
    field :candidates, {:array, :map}, default: []
    field :journal_visibility, :string, default: "private"

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(organization_id state sport activity_type title started_at started_tz
             duration_seconds distance_meters avg_heart_rate max_heart_rate calories class_id
             merged_kind merged_id candidates journal_visibility)a

  def changeset(activity \\ %__MODULE__{}, attrs) do
    activity
    |> cast(attrs, [:user_id, :provider, :provider_activity_id | @fields])
    |> validate_required([
      :user_id,
      :provider,
      :provider_activity_id,
      :state,
      :sport,
      :title,
      :started_at,
      :duration_seconds
    ])
    |> validate_inclusion(:provider, Catalog.providers())
    |> validate_inclusion(:state, Catalog.activity_states())
    |> validate_length(:title, min: 1, max: 160)
    |> unique_constraint([:user_id, :provider, :provider_activity_id])
    |> check_constraint(:state, name: :device_activities_state_check)
    |> check_constraint(:journal_visibility, name: :device_activities_journal_visibility_check)
    |> check_constraint(:duration_seconds, name: :device_activities_numbers_check)
  end
end
