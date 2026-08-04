defmodule MilosTraining.Application.ListFinanceCleanupRecords do
  alias MilosTraining.Finance

  def call(params \\ %{}) do
    {:ok, %{records: Finance.list_finance_cleanup_records(params)}}
  end
end
