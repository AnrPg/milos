defmodule Palee.Finance.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Finance.Domain.MemberStatus

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :user_type_snapshot, :string
    field :status, :string, default: "trial"
    # ADR-274: the status staff see, worked out from subscriptions and charges.
    field :status_shown, :string
    field :signup_source, :string, default: "admin_created"
    field :starts_on, :date
    field :expires_on, :date
    field :notes, :string
    field :referred_by_user_id, :binary_id
    field :params, :map, default: %{}
    field :entitlement_status, :string, default: "inactive"
    field :entitlement_source, :string
    field :entitlement_expires_on, :date
    field :entitlement_updated_at, :utc_datetime_usec
    field :last_payment_reminder_sent_at, :utc_datetime_usec
    # ADR-220: the member is leaving (or left) the box on `leaving_on`.
    field :leaving_on, :date
    field :left_at, :utc_datetime_usec
    field :left_by, :string
    field :leave_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership \\ %__MODULE__{}, params) do
    membership
    |> cast(params, [
      :user_id,
      :user_type_snapshot,
      :status,
      :signup_source,
      :starts_on,
      :expires_on,
      :notes,
      :referred_by_user_id,
      :params,
      :entitlement_status,
      :entitlement_source,
      :entitlement_expires_on,
      :entitlement_updated_at,
      :last_payment_reminder_sent_at
    ])
    |> validate_required([:user_id, :user_type_snapshot, :status, :signup_source])
    |> validate_inclusion(:user_type_snapshot, ["member", "athlete", "guest"])
    |> validate_inclusion(:status, [
      "active",
      "expiring",
      "expired",
      "cancelled",
      "paused",
      "trial",
      "comped"
    ])
    |> validate_inclusion(:signup_source, [
      "direct",
      "referral",
      "promo",
      "admin_created",
      "migrated",
      "imported"
    ])
    |> validate_inclusion(:entitlement_status, ["active", "grace", "blocked", "inactive"])
    |> unique_constraint([:organization_id, :user_id], name: :memberships_organization_user_index)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:referred_by_user_id)
  end

  @doc """
  ADR-220: records (or, with every field nil, clears) the member leaving the
  box. Kept out of `changeset/2` so a plain membership update cannot set it.
  """
  def leave_changeset(%__MODULE__{} = membership, params) do
    membership
    |> cast(params, [:leaving_on, :left_at, :left_by, :leave_reason, :expires_on, :status])
    |> validate_inclusion(:left_by, ["member", "staff"])
    |> validate_length(:leave_reason, max: 500)
    |> check_constraint(:leaving_on, name: :leaving_consistency_check)
  end

  @doc """
  ADR-274: the worked-out status (or the one staff set by hand). Kept out of
  `changeset/2` so a plain membership update cannot set what staff see.
  """
  def status_changeset(%__MODULE__{} = membership, params) do
    membership
    |> cast(params, [:status, :status_shown])
    |> validate_inclusion(:status, MemberStatus.lifecycles())
    |> validate_inclusion(:status_shown, MemberStatus.statuses())
  end
end
