defmodule MilosTraining.Finance.Commands.CreateReferralReward do
  alias MilosTraining.Finance.FinanceStore

  def call(referral_event_id, params),
    do: FinanceStore.create_referral_reward(referral_event_id, params)
end
