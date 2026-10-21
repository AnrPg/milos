defmodule Palee.Finance.Commands.IssueInvoice do
  alias Palee.Finance.FinanceStore

  def call(invoice_id, params), do: FinanceStore.issue_invoice(invoice_id, params)
end
