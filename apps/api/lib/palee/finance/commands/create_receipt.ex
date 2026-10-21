defmodule Palee.Finance.Commands.CreateReceipt do
  alias Palee.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.create_receipt(membership_id, params)
end
