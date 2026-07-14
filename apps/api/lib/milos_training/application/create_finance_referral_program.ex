defmodule MilosTraining.Application.CreateFinanceReferralProgram do
  alias MilosTraining.Finance

  def call(params), do: Finance.create_referral_program(params)
end
