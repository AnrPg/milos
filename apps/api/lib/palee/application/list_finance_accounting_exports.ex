defmodule Palee.Application.ListFinanceAccountingExports do
  @moduledoc "Accounting export run history (ADR-126), newest first."

  alias Palee.Finance

  def call(%{organization_id: organization_id} = context, params)
      when is_binary(organization_id) do
    {:ok, %{accounting_exports: Finance.list_accounting_exports(context, params || %{})}}
  end

  def call(_context, _params), do: {:error, :organization_context_required}
end
