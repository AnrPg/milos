defmodule MilosTraining.Finance.Commands.ReverseCreditLedgerEntry do
  alias MilosTraining.Finance.FinanceStore

  def call(membership_id, entry_id, params),
    do: FinanceStore.reverse_credit_ledger_entry(membership_id, entry_id, params)
end
