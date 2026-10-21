defmodule Palee.Application.UpdateFinanceReferralProgram do
  alias Palee.Finance

  def call(id, params), do: Finance.update_referral_program(id, params)
end
