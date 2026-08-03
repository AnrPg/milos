defmodule MilosTraining.Finance.Commands.CreateReceipt do
  alias MilosTraining.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.create_receipt(membership_id, params)
end
