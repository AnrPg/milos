defmodule Palee.Finance.Commands.GenerateRenewalInvoice do
  alias Palee.Finance.FinanceStore

  def call(membership_id, params),
    do: FinanceStore.generate_renewal_invoice(membership_id, params)
end
