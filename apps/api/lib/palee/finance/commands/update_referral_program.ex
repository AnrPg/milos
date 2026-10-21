defmodule Palee.Finance.Commands.UpdateReferralProgram do
  alias Palee.Finance.FinanceStore

  def call(id, params), do: FinanceStore.update_referral_program(id, params)
end
