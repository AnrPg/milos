defmodule Palee.Scheduling.Booking do
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Scheduling.ScheduledClass

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses [:pending, :approved, :rejected, :cancelled, :waitlisted]
  @allowances ["class_visits", "event_visits", "guest_passes", "none"]
  # ADR-144: what a booking is. A trial seat draws no allowance ("none").
  @kinds ["member", "guest", "trial"]

  schema "bookings" do
    field :organization_id, :binary_id
    belongs_to :scheduled_class, ScheduledClass
    field :user_id, :binary_id
    field :status, Ecto.Enum, values: @statuses
    field :admin_message, :string
    field :timeout_job_id, :integer
    field :client_operation_id, Ecto.UUID
    field :resolution_operation_id, Ecto.UUID
    field :waitlist_priority, :integer, default: 0
    field :waitlisted_at, :utc_datetime_usec
    field :guest_name, :string
    field :entitlement_allowance, :string, default: "class_visits"
    field :kind, :string, default: "member"

    timestamps()
  end

  def create_changeset(booking \\ %__MODULE__{}, params) do
    booking
    |> cast(params, [
      :organization_id,
      :scheduled_class_id,
      :user_id,
      :status,
      :client_operation_id,
      :waitlist_priority,
      :waitlisted_at,
      :guest_name,
      :entitlement_allowance,
      :kind
    ])
    |> put_guest_kind()
    |> validate_required([:organization_id, :scheduled_class_id, :user_id, :status, :kind])
    |> validate_inclusion(:entitlement_allowance, @allowances)
    |> validate_inclusion(:kind, @kinds)
    |> validate_trial_allowance()
    |> validate_length(:guest_name, min: 2, max: 80)
    |> foreign_key_constraint(:scheduled_class_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id, name: :bookings_slot_user_index)
    |> unique_constraint(:client_operation_id, name: :bookings_client_operation_index)
  end

  def resolution_changeset(booking, params) do
    booking
    |> cast(params, [:status, :admin_message, :resolution_operation_id])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:approved, :rejected])
  end

  def timeout_changeset(booking, params) do
    booking
    |> cast(params, [:status, :admin_message])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:cancelled])
  end

  def timeout_job_changeset(booking, job_id) do
    booking
    |> change(timeout_job_id: job_id)
  end

  @doc "Moves a waitlist entry into the normal booking flow (ADR-097)."
  def promotion_changeset(booking, status) when status in [:pending, :approved] do
    change(booking, status: status, waitlisted_at: nil)
  end

  def statuses, do: @statuses
  def kinds, do: @kinds

  defp put_guest_kind(changeset) do
    if get_field(changeset, :guest_name) not in [nil, ""] and
         get_field(changeset, :kind) == "member",
       do: put_change(changeset, :kind, "guest"),
       else: changeset
  end

  # Mirrors bookings_trial_allowance_check: trials, and only trials, skip the ledger.
  defp validate_trial_allowance(changeset) do
    trial? = get_field(changeset, :kind) == "trial"
    none? = get_field(changeset, :entitlement_allowance) == "none"

    if trial? == none?,
      do: changeset,
      else:
        add_error(changeset, :entitlement_allowance, "must be none exactly for trial bookings")
  end
end
