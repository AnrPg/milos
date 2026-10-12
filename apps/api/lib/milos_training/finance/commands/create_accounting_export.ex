defmodule MilosTraining.Finance.Commands.CreateAccountingExport do
  @moduledoc "Records a requested accounting export run (ADR-116)."

  alias MilosTraining.Finance.FinanceAccountingStore

  def call(attrs), do: FinanceAccountingStore.create_accounting_export(attrs)
end
