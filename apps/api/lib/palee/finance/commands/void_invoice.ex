defmodule Palee.Finance.Commands.VoidInvoice do
  alias Palee.Finance.FinanceStore

  def call(invoice_id, params), do: FinanceStore.void_invoice(invoice_id, params)
end
