defmodule MilosTraining.Application.UpdateFinanceReferralRewardStatus do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(id, status) do
    with {:ok, reward} <- Finance.update_referral_reward_status(id, status) do
      RecordAnalyticsEvent.call_unsafe("referral_reward_status_changed", %{
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
