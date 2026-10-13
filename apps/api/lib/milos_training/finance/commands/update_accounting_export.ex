defmodule MilosTraining.Finance.Commands.UpdateAccountingExport do
  @moduledoc "Advances an accounting export run (running, completed, failed)."

  alias MilosTraining.Finance.FinanceAccountingStore

  def call(id, attrs), do: FinanceAccountingStore.update_accounting_export(id, attrs)
end
