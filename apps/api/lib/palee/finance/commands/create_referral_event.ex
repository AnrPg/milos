defmodule Palee.Finance.Commands.CreateReferralEvent do
  alias Palee.Finance.FinanceStore

  def call(params), do: FinanceStore.create_referral_event(params)
end
