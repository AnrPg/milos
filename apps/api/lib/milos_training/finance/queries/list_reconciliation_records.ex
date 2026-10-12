defmodule MilosTraining.Finance.Queries.ListReconciliationRecords do
  @moduledoc "Reconciliation records, optionally filtered by status or provider."

  alias MilosTraining.Finance.FinanceAccountingStore

  def call(filters), do: FinanceAccountingStore.list_reconciliation_records(filters)
end
