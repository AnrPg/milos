defmodule Palee.Finance.Queries.ListReconciliationRecords do
  @moduledoc "Reconciliation records, optionally filtered by status or provider."

  alias Palee.Finance.FinanceAccountingStore

  def call(filters), do: FinanceAccountingStore.list_reconciliation_records(filters)
end
