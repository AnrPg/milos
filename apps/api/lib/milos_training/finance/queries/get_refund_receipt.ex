defmodule MilosTraining.Finance.Queries.GetRefundReceipt do
  @moduledoc "One refund receipt of the tenant, or nil."

  alias MilosTraining.Finance.FinanceAccountingStore

  def call(id), do: FinanceAccountingStore.get_refund_receipt(id)

  def for_reversal(reversal_id),
    do: FinanceAccountingStore.get_refund_receipt_for_reversal(reversal_id)
end
