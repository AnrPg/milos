defmodule MilosTraining.Application.MatchFinanceReconciliationRecord do
  @moduledoc """
  Matches a statement line to an internal payment (`target_type: payment`)
  or reversal (`target_type: reversal`) fact (ADR-126). The record becomes
  `matched` or, when the domain rules find discrepancies, `mismatched` and
  flagged for review. Internal facts are never modified.
  """

  alias MilosTraining.Finance

  def call(%{organization_id: organization_id} = context, record_id, actor_id, params)
      when is_binary(organization_id) do
    params = params || %{}

    Finance.match_reconciliation_record(
      context,
      record_id,
      value(params, "target_type", :target_type),
      value(params, "target_id", :target_id),
      %{actor_id: actor_id, notes: value(params, "notes", :notes)}
    )
  end

  def call(_context, _record_id, _actor_id, _params),
    do: {:error, :organization_context_required}

  defp value(params, key, atom_key), do: Map.get(params, key, Map.get(params, atom_key))
end
