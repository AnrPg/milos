defmodule Palee.Finance.Commands.CreateInvoice do
  alias Palee.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.create_invoice(membership_id, params)
end
