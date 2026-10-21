defmodule Palee.Application.ListFinanceReconciliationRecords do
  @moduledoc "Lists reconciliation records with optional `status`, `provider` and `limit` filters."

  alias Palee.Finance

  def call(%{organization_id: organization_id} = context, params)
      when is_binary(organization_id) do
    {:ok, %{reconciliation_records: Finance.list_reconciliation_records(context, params || %{})}}
  end

  def call(_context, _params), do: {:error, :organization_context_required}
end
