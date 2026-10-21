defmodule Palee.Finance.Commands.CreateManualCredit do
  alias Palee.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.create_manual_credit(membership_id, params)
end
