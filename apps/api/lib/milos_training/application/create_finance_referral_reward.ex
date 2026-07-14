defmodule MilosTraining.Application.CreateFinanceReferralReward do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(referral_event_id, params) do
    with {:ok, reward} <- Finance.create_referral_reward(referral_event_id, params) do
      RecordAnalyticsEvent.call_unsafe("referral_reward_created", %{
        user_id: reward.recipient_user_id,
        context_type: "referral_reward",
        context_id: reward.id,
        metadata: %{
          referral_event_id: reward.referral_event_id,
          membership_id: reward.membership_id,
          reward_type: reward.reward_type,
          reward_value: reward.reward_value,
          status: reward.status
        }
      })

      {:ok, reward}
    end
  end
end
