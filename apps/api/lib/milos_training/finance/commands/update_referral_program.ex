defmodule MilosTraining.Finance.Commands.UpdateReferralProgram do
  alias MilosTraining.Finance.FinanceStore

  def call(id, params), do: FinanceStore.update_referral_program(id, params)
end
