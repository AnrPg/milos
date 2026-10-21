defmodule MilosTraining.Trials.TrialRequest do
  @moduledoc """
  One person's trial at one box, from the ask to the outcome (ADR-144). The
  seat itself is a `kind: "trial"` booking; this row is the funnel: requested
  or booked, then attended or no-show, then converted when they join.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Trials.Domain.TrialLifecycle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "scheduling_trial_requests" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :scheduled_class_id, :binary_id
    field :booking_id, :binary_id
    field :status, :string
    field :note, :string
    field :phone, :string
    field :source, :string, default: "box_page"
    field :client_operation_id, Ecto.UUID
    field :class_starts_at, :utc_datetime_usec
    field :class_name, :string
    field :decided_at, :utc_datetime_usec
    field :decided_by_id, :binary_id
    field :decline_reason, :string
    field :attended_at, :utc_datetime_usec
    field :converted_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :join_interest_at, :utc_datetime_usec
    field :follow_up_dismissed_at, :utc_datetime_usec
    # The club event whose trial offer this came from (ADR-153), a plain id.
    field :referral_event_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @sources ~w(box_page schedule qr_door referral event admin)

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :user_id,
      :scheduled_class_id,
      :booking_id,
      :status,
      :note,
      :phone,
      :source,
      :client_operation_id,
      :class_starts_at,
      :class_name,
      :decided_at,
      :referral_event_id
    ])
    |> validate_required([:organization_id, :user_id, :status, :class_starts_at, :source])
    |> validate_inclusion(:status, ["requested", "booked"])
    |> validate_inclusion(:source, @sources)
    |> validate_length(:note, max: 500)
    |> validate_format(:phone, ~r/^\+?[0-9 ()\-]{6,24}$/)
    |> unique_constraint([:organization_id, :user_id], name: :trial_requests_one_open_index)
    |> unique_constraint([:user_id, :client_operation_id], name: :trial_requests_operation_index)
  end

  @doc "Applies a lifecycle step the domain already allowed."
  def transition_changeset(request, changes) do
    request
    |> cast(changes, [
      :status,
      :booking_id,
      :decided_at,
      :decided_by_id,
      :decline_reason,
      :attended_at,
      :converted_at,
      :cancelled_at,
      :join_interest_at,
      :follow_up_dismissed_at
    ])
    |> validate_inclusion(:status, TrialLifecycle.statuses())
    |> validate_length(:decline_reason, max: 300)
  end

  def sources, do: @sources
end
