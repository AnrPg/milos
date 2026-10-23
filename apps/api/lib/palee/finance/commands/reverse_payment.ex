defmodule Palee.Finance.Commands.ReversePayment do
  alias Palee.Finance.{FinanceStore, RevenueTelemetry}

  def call(membership_id, payment_id, params) do
    membership_id
    |> FinanceStore.reverse_payment(payment_id, params)
    |> RevenueTelemetry.observe_reversal()
  end
end
