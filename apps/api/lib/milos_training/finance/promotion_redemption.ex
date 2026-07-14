defmodule MilosTraining.Finance.PromotionRedemption do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "promotion_redemptions" do
    field :promotion_campaign_id, :binary_id
    field :promotion_code_id, :binary_id
    field :membership_id, :binary_id
    field :membership_payment_id, :binary_id
    field :membership_package_subscription_id, :binary_id
    field :discount_type_snapshot, :string
    field :discount_value_snapshot, :integer, default: 0
    field :redeemed_at, :utc_datetime_usec
    field :params, :map, default: %{}
  end

  def changeset(redemption \\ %__MODULE__{}, params) do
    redemption
    |> cast(params, [
      :promotion_campaign_id,
      :promotion_code_id,
      :membership_id,
      :membership_payment_id,
      :membership_package_subscription_id,
      :discount_type_snapshot,
      :discount_value_snapshot,
      :redeemed_at,
      :params
    ])
    |> validate_required([
      :promotion_campaign_id,
      :membership_id,
      :discount_type_snapshot,
      :discount_value_snapshot,
      :redeemed_at
    ])
    |> validate_inclusion(:discount_type_snapshot, [
      "percent",
      "fixed_amount",
      "free_period",
      "manual"
    ])
    |> validate_number(:discount_value_snapshot, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:promotion_campaign_id)
    |> foreign_key_constraint(:promotion_code_id)
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:membership_payment_id)
    |> foreign_key_constraint(:membership_package_subscription_id)
  end
end
