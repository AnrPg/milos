defmodule MilosTraining.Finance.Commands.ApplyCreditToPayment do
  alias MilosTraining.Finance.FinanceStore

  def call(membership_id, payment_id, params),
    do: FinanceStore.apply_credit_to_payment(membership_id, payment_id, params)
end
