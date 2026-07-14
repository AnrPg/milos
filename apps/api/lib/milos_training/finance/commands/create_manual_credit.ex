defmodule MilosTraining.Finance.Commands.CreateManualCredit do
  alias MilosTraining.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.create_manual_credit(membership_id, params)
end
