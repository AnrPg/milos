defmodule MilosTraining.Finance.Commands.MatchReconciliationRecord do
  @moduledoc """
  Links a statement line to one internal payment or reversal fact and records
  the discrepancies the domain rules find (ADR-108).
  """

  alias MilosTraining.Finance.Domain.ReconciliationMatching
  alias MilosTraining.Finance.FinanceAccountingStore

  def call(record_id, target_type, target_id, attrs) do
    with {:ok, target_kind} <- ReconciliationMatching.parse_target_type(target_type),
         {:ok, _uuid} <- cast_target(target_id) do
      FinanceAccountingStore.match_reconciliation_record(record_id, target_kind, target_id, attrs)
    end
  end

  defp cast_target(target_id) do
    case Ecto.UUID.cast(target_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_reconciliation_target}
    end
  end
end
