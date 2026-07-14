defmodule MilosTraining.Finance.Commands.VoidInvoice do
  alias MilosTraining.Finance.FinanceStore

  def call(invoice_id, params), do: FinanceStore.void_invoice(invoice_id, params)
end
