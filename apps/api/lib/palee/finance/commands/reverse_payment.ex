defmodule Palee.Finance.Commands.ReversePayment do
  alias Palee.Finance.FinanceStore

  def call(membership_id, payment_id, params),
    do: FinanceStore.reverse_payment(membership_id, payment_id, params)
end
