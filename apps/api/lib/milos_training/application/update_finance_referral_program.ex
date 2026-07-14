defmodule MilosTraining.Application.UpdateFinanceReferralProgram do
  alias MilosTraining.Finance

  def call(id, params), do: Finance.update_referral_program(id, params)
end
