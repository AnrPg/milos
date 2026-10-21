defmodule Palee.Finance.Commands.CreateAccountingExport do
  @moduledoc "Records a requested accounting export run (ADR-126)."

  alias Palee.Finance.FinanceAccountingStore

  def call(attrs), do: FinanceAccountingStore.create_accounting_export(attrs)
end
