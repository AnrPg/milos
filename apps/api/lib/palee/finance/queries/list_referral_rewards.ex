defmodule Palee.Finance.Queries.ListReferralRewards do
  alias Palee.Finance.FinanceStore

  def call, do: FinanceStore.list_referral_rewards()
end
