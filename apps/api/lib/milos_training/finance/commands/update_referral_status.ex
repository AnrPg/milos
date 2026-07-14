defmodule MilosTraining.Finance.Commands.UpdateReferralStatus do
  alias MilosTraining.Finance.FinanceStore

  def call(id, status), do: FinanceStore.update_referral_status(id, status)
end
