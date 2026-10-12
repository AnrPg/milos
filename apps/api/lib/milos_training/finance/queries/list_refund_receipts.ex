defmodule MilosTraining.Finance.Queries.ListRefundReceipts do
  @moduledoc "Refund receipts of the tenant, newest number first (ADR-116)."

  alias MilosTraining.Finance.FinanceAccountingStore

  def call(filters), do: FinanceAccountingStore.list_refund_receipts(filters)
end
