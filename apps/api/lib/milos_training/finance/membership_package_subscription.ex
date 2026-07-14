defmodule MilosTraining.Finance.MembershipPackageSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "membership_package_subscriptions" do
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
      :referral_reward_applied
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
