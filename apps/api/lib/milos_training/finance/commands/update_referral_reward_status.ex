defmodule MilosTraining.Finance.Commands.UpdateReferralRewardStatus do
  alias MilosTraining.Finance.FinanceStore

  def call(id, status), do: FinanceStore.update_referral_reward_status(id, status)
end
