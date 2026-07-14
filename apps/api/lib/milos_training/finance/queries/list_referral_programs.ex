defmodule MilosTraining.Finance.Queries.ListReferralPrograms do
  alias MilosTraining.Finance.FinanceStore

  def call, do: FinanceStore.list_referral_programs()
end
