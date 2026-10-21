defmodule Palee.Finance.Commands.RecordPayment do
  alias Palee.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.record_payment(membership_id, params)
end
