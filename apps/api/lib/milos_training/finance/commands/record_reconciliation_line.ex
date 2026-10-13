defmodule MilosTraining.Finance.Commands.RecordReconciliationLine do
  @moduledoc "Records (idempotently) one external provider statement line (ADR-126)."

  alias MilosTraining.Finance.Domain.ReconciliationMatching
  alias MilosTraining.Finance.FinanceAccountingStore

  def call(params, actor_id) do
    case ReconciliationMatching.normalize_statement_line(params) do
      {:ok, line} -> FinanceAccountingStore.record_reconciliation_line(line, actor_id)
      {:error, errors} -> {:error, errors}
    end
  end
end
