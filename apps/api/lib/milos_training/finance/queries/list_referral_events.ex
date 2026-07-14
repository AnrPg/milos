defmodule MilosTraining.Finance.Queries.ListReferralEvents do
  alias MilosTraining.Finance.FinanceStore

  def call, do: FinanceStore.list_referral_events()
end
