defmodule MilosTraining.Finance.Queries.ListFinanceCleanupRecords do
  alias MilosTraining.Finance.FinanceStore

  def call(params), do: FinanceStore.list_finance_cleanup_records(params)
end
