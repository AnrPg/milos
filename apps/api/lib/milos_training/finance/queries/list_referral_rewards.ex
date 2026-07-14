defmodule MilosTraining.Finance.Queries.ListReferralRewards do
  alias MilosTraining.Finance.FinanceStore

  def call, do: FinanceStore.list_referral_rewards()
end
