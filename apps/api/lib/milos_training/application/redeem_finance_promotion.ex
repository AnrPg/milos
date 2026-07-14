defmodule MilosTraining.Application.RedeemFinancePromotion do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(user_id, params) do
    case Finance.get_member_profile(user_id) do
      nil ->
        {:error, :not_found}

      profile ->
        with {:ok, redemption} <- Finance.redeem_promotion(profile.membership.id, params) do
          RecordAnalyticsEvent.call_unsafe("promotion_redeemed", %{
            user_id: user_id,
            context_type: "promotion_redemption",
            context_id: redemption.id,
            metadata: %{
              membership_id: profile.membership.id,
              promotion_campaign_id: redemption.promotion_campaign_id,
              promotion_code_id: redemption.promotion_code_id,
              discount_type: redemption.discount_type_snapshot,
              discount_value: redemption.discount_value_snapshot
            }
          })

          {:ok, redemption}
        end
    end
  end
end
