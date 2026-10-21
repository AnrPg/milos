defmodule Palee.Seasons.SeasonEnrollment do
  @moduledoc """
  One member's place in a season (ADR-167): a request the staff confirm or
  decline, a waitlist place when the season is full, then active until the
  season completes. One row per member and season; asking again after a
  decline or a cancel re-uses it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Seasons.Domain.EnrollmentLifecycle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "season_enrollments" do
    field :organization_id, :binary_id, read_after_writes: true
    field :season_offering_id, :binary_id
    field :user_id, :binary_id
    field :status, :string
    field :requested_at, :utc_datetime_usec
    field :decided_at, :utc_datetime_usec
    field :decided_by_id, :binary_id
    field :decline_reason, :string
    field :cancelled_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :package_subscription_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :season_offering_id, :user_id, :status, :requested_at])
    |> validate_required([:season_offering_id, :user_id, :status, :requested_at])
    |> validate_inclusion(:status, EnrollmentLifecycle.statuses())
    |> unique_constraint([:season_offering_id, :user_id])
  end

  @doc "Applies a lifecycle step the domain already allowed."
  def transition_changeset(enrollment, changes) do
    enrollment
    |> cast(changes, [
      :status,
      :requested_at,
      :decided_at,
      :decided_by_id,
      :decline_reason,
      :cancelled_at,
      :completed_at,
      :package_subscription_id
    ])
    |> validate_inclusion(:status, EnrollmentLifecycle.statuses())
    |> validate_length(:decline_reason, max: 300)
  end
end
