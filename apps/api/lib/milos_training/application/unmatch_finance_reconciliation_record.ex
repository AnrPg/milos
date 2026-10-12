defmodule MilosTraining.Application.UnmatchFinanceReconciliationRecord do
  @moduledoc "Clears a statement line's match so it can be matched again (ADR-108)."

  alias MilosTraining.Finance

  def call(%{organization_id: organization_id} = context, record_id, actor_id, params)
      when is_binary(organization_id) do
    notes = (params || %{}) |> Map.get("notes", Map.get(params || %{}, :notes))
    Finance.unmatch_reconciliation_record(context, record_id, %{actor_id: actor_id, notes: notes})
  end

  def call(_context, _record_id, _actor_id, _params),
    do: {:error, :organization_context_required}
end
