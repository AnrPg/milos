defmodule MilosTraining.Finance.Queries.ReconciliationCandidates do
  @moduledoc """
  Internal facts that could match a statement line, ranked by the domain
  rules (exact amount first, then nearest date) with each candidate's
  evaluation (ADR-116).
  """

  alias MilosTraining.Finance.Domain.ReconciliationMatching
  alias MilosTraining.Finance.FinanceAccountingStore

  def call(record_id) do
    with {:ok, record, facts} <- FinanceAccountingStore.reconciliation_candidate_facts(record_id) do
      {:ok, %{record: record, candidates: ReconciliationMatching.rank_candidates(record, facts)}}
    end
  end
end
