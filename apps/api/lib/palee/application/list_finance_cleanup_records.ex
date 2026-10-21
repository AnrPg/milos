defmodule Palee.Application.ListFinanceCleanupRecords do
  alias Palee.Finance

  def call(params \\ %{}) do
    {:ok, %{records: Finance.list_finance_cleanup_records(params)}}
  end
end
