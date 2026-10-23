defmodule Palee.Finance.Commands.RecordPayment do
  alias Palee.Finance.{FinanceStore, RevenueTelemetry}

  def call(membership_id, params),
    do: membership_id |> FinanceStore.record_payment(params) |> RevenueTelemetry.observe_payment()
end
