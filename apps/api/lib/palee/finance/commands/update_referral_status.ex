defmodule Palee.Finance.Commands.UpdateReferralStatus do
  alias Palee.Finance.FinanceStore

  def call(id, status), do: FinanceStore.update_referral_status(id, status)
end
