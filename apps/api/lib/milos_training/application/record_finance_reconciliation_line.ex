defmodule MilosTraining.Application.RecordFinanceReconciliationLine do
  @moduledoc """
  Records one external payment-provider statement line (ADR-108). Idempotent
  on (organization, provider, external_reference): an identical replay
  returns the existing record with outcome `:replayed`; a replay with
  different economic content fails with `:reconciliation_reference_conflict`.
  """

  alias MilosTraining.Finance

  def call(%{organization_id: organization_id} = context, actor_id, params)
      when is_binary(organization_id) and is_map(params) do
    Finance.record_reconciliation_line(context, params, actor_id)
  end

  def call(_context, _actor_id, _params), do: {:error, :organization_context_required}
end
