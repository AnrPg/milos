defmodule MilosTraining.Finance.Commands.IssueInvoice do
  alias MilosTraining.Finance.FinanceStore

  def call(invoice_id, params), do: FinanceStore.issue_invoice(invoice_id, params)
end
