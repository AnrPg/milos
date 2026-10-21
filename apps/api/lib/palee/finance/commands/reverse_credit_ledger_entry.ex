defmodule Palee.Finance.Commands.ReverseCreditLedgerEntry do
  alias Palee.Finance.FinanceStore

  def call(membership_id, entry_id, params),
    do: FinanceStore.reverse_credit_ledger_entry(membership_id, entry_id, params)
end
