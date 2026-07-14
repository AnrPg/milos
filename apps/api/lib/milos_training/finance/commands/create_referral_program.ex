defmodule MilosTraining.Finance.Commands.CreateReferralProgram do
  alias MilosTraining.Finance.FinanceStore

  def call(params), do: FinanceStore.create_referral_program(params)
end
