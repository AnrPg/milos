defmodule Palee.Finance.Queries.AccountingExportRows do
  @moduledoc "Rows of every accounting export dataset for an inclusive date range."

  alias Palee.Finance.FinanceAccountingStore

  def call(range_start, range_end),
    do: FinanceAccountingStore.accounting_export_rows(range_start, range_end)
end
