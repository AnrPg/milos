defmodule Palee.Community.EventAttendee do
  @moduledoc """
  A person on an event (ADR-153): going, on the waitlist, or no longer
  coming; how they got there (a club `member`, anyone on an `open` event, a
  `guest` a going member invited); and what staff recorded: paid, came.
  One row per person and event; changing your mind updates it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(going waitlisted cancelled)
  @sources ~w(member open guest)
  @payment_methods ~w(cash bank_transfer card_manual other)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "community_event_attendees" do
    field :organization_id, :binary_id, read_after_writes: true
    field :event_id, :binary_id
    field :user_id, :binary_id
    field :status, :string
    field :source, :string
    field :invited_by_id, :binary_id
    field :queued_at, :utc_datetime_usec
    field :promoted_at, :utc_datetime_usec
    field :paid_at, :utc_datetime_usec
    field :paid_recorded_by_id, :binary_id
    field :payment_method, :string
    field :amount_cents, :integer
    field :finance_invoice_id, :binary_id
    field :finance_payment_id, :binary_id
    field :checked_in_at, :utc_datetime_usec
    field :checked_in_by_id, :binary_id
    field :cancelled_at, :utc_datetime_usec
    field :late_cancel, :boolean, default: false
    field :removed_by_id, :binary_id
    field :trial_offered_at, :utc_datetime_usec
    field :converted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses
  def sources, do: @sources
  def payment_methods, do: @payment_methods

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :event_id,
      :user_id,
      :status,
      :source,
      :invited_by_id,
      :queued_at,
      :promoted_at
    ])
    |> validate_required([:event_id, :user_id, :status, :source, :queued_at])
    |> validate()
    |> unique_constraint([:event_id, :user_id],
      name: :community_event_attendees_event_id_user_id_index
    )
  end

  def update_changeset(attendee, attrs) do
    attendee
    |> cast(attrs, [
      :status,
      :source,
      :invited_by_id,
      :queued_at,
      :promoted_at,
      :paid_at,
      :paid_recorded_by_id,
      :payment_method,
      :amount_cents,
      :finance_invoice_id,
      :finance_payment_id,
      :checked_in_at,
      :checked_in_by_id,
      :cancelled_at,
      :late_cancel,
      :removed_by_id,
      :trial_offered_at,
      :converted_at
    ])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> check_constraint(:status, name: :community_event_attendees_cancel_check)
    |> check_constraint(:source, name: :community_event_attendees_source_check)
    |> check_constraint(:payment_method, name: :community_event_attendees_payment_check)
  end
end
