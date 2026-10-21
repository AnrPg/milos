defmodule Palee.Application.CreateFinanceReferralProgram do
  alias Palee.Finance

  def call(params), do: Finance.create_referral_program(params)
end
