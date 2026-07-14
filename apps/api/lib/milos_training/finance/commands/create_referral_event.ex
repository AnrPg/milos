defmodule MilosTraining.Finance.Commands.CreateReferralEvent do
  alias MilosTraining.Finance.FinanceStore

  def call(params), do: FinanceStore.create_referral_event(params)
end
