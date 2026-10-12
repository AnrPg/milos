defmodule MilosTraining.Finance.Queries.GetAccountingExport do
  @moduledoc "One accounting export run of the tenant, or nil."

  alias MilosTraining.Finance.FinanceAccountingStore

  def call(id), do: FinanceAccountingStore.get_accounting_export(id)
end
