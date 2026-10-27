defmodule Palee.Finance.MembershipPackageSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "membership_package_subscriptions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_id, :binary_id
    field :membership_package_id, :binary_id
    field :status, :string, default: "active"
    field :starts_on, :date
    field :ends_on, :date
    field :package_code_snapshot, :string
    field :package_family_snapshot, :string
    field :billing_period_snapshot, :string
    field :price_cents_snapshot, :integer, default: 0
    field :params_snapshot, :map, default: %{}
    field :referral_reward_applied, :boolean, default: false
    field :commitment_ends_on, :date
    field :activated_on, :date
    # ADR-098: an add-on follows its base; a corporate seat is paid by a client.
    field :base_subscription_id, :binary_id
    field :corporate_client_id, :binary_id
    # ADR-205: `code` or `email_domain` for a seat the member took; nil when
    # an admin added it. An email-domain seat ends when the email leaves it.
    field :corporate_enrolled_via, :string
    field :expiry_reminder_sent_at, :utc_datetime_usec
    field :grace_notice_sent_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(subscription \\ %__MODULE__{}, params) do
    subscription
    |> cast(params, [
      :membership_id,
      :membership_package_id,
      :status,
      :starts_on,
      :ends_on,
      :package_code_snapshot,
      :package_family_snapshot,
      :billing_period_snapshot,
      :price_cents_snapshot,
      :params_snapshot,
      :referral_reward_applied,
      :commitment_ends_on,
      :activated_on,
      :base_subscription_id,
      :corporate_client_id,
      :corporate_enrolled_via,
      :expiry_reminder_sent_at,
      :grace_notice_sent_at
    ])
    |> validate_required([
      :membership_id,
      :membership_package_id,
      :status,
      :package_code_snapshot,
      :package_family_snapshot,
      :billing_period_snapshot
    ])
    |> validate_inclusion(:status, ["active", "paused", "cancelled", "expired"])
    |> validate_inclusion(:corporate_enrolled_via, ["code", "email_domain"])
    |> validate_number(:price_cents_snapshot, greater_than_or_equal_to: 0)
    |> validate_date_window()
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:membership_package_id)
  end

  defp validate_date_window(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.compare(ends_on, starts_on) == :lt do
      add_error(changeset, :ends_on, "must be on or after the start date")
    else
      changeset
    end
  end
end
