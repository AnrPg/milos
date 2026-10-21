defmodule Palee.Finance.Commands.UpdateReferralRewardStatus do
  alias Palee.Finance.FinanceStore

  def call(id, status), do: FinanceStore.update_referral_reward_status(id, status)
end
