defmodule Palee.Finance.Commands.ApplyCreditToInvoice do
  alias Palee.Finance.FinanceStore

  def call(membership_id, invoice_id, params),
    do: FinanceStore.apply_credit_to_invoice(membership_id, invoice_id, params)
end
