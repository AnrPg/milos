defmodule MilosTraining.Finance.Commands.ApplyCreditToInvoice do
  alias MilosTraining.Finance.FinanceStore

  def call(membership_id, invoice_id, params),
    do: FinanceStore.apply_credit_to_invoice(membership_id, invoice_id, params)
end
