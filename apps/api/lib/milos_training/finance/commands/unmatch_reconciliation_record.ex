defmodule MilosTraining.Finance.Commands.UnmatchReconciliationRecord do
  @moduledoc "Clears a statement line's match so it can be matched again (ADR-126)."

  alias MilosTraining.Finance.FinanceAccountingStore

  def call(record_id, attrs),
    do: FinanceAccountingStore.unmatch_reconciliation_record(record_id, attrs)
end
