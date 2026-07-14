defmodule MilosTraining.Finance.Commands.GenerateRenewalInvoice do
  alias MilosTraining.Finance.FinanceStore

  def call(membership_id, params),
    do: FinanceStore.generate_renewal_invoice(membership_id, params)
end
