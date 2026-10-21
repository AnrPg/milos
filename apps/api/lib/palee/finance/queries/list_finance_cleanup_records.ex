defmodule Palee.Finance.Queries.ListFinanceCleanupRecords do
  alias Palee.Finance.FinanceStore

  def call(params), do: FinanceStore.list_finance_cleanup_records(params)
end
