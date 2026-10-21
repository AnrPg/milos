defmodule Palee.Finance.Queries.GetReconciliationRecord do
  @moduledoc "One reconciliation record of the tenant, or nil."

  alias Palee.Finance.FinanceAccountingStore

  def call(id), do: FinanceAccountingStore.get_reconciliation_record(id)
end
