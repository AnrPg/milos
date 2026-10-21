defmodule Palee.Finance.Queries.ListAccountingExports do
  @moduledoc "Accounting export runs of the tenant, newest first."

  alias Palee.Finance.FinanceAccountingStore

  def call(filters), do: FinanceAccountingStore.list_accounting_exports(filters)
end
