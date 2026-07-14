defmodule MilosTraining.Finance.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :user_id, :binary_id
    field :user_type_snapshot, :string
    field :status, :string, default: "trial"
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
    |> validate_inclusion(:user_type_snapshot, ["member", "athlete"])
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
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:referred_by_user_id)
  end
end
