defmodule Palee.Finance.Queries.ListReferralEvents do
  alias Palee.Finance.FinanceStore

  def call, do: FinanceStore.list_referral_events()
end
