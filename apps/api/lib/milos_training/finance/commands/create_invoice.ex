defmodule MilosTraining.Finance.Commands.CreateInvoice do
  alias MilosTraining.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.create_invoice(membership_id, params)
end
