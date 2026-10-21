defmodule Palee.Finance.Commands.CreateReferralProgram do
  alias Palee.Finance.FinanceStore

  def call(params), do: FinanceStore.create_referral_program(params)
end
