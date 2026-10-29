defmodule Palee.Finance.Commands.ReceivePayment do
  alias Palee.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.receive_payment(membership_id, params)
end
