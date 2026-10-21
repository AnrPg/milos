defmodule Palee.Finance.Queries.ListRefundReceipts do
  @moduledoc "Refund receipts of the tenant, newest number first (ADR-126)."

  alias Palee.Finance.FinanceAccountingStore

  def call(filters), do: FinanceAccountingStore.list_refund_receipts(filters)
end
