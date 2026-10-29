defmodule Palee.Fiscal.TaxStore do
  @moduledoc false
  @behaviour Palee.Fiscal.Ports.TaxStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :fiscal_tax_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun), do: tenant_call(context, :transaction, [fun])

  @impl true
  def list_sales_tax_rates(context), do: tenant_call(context, :list_sales_tax_rates, [])

  @impl true
  def replace_sales_tax_rates(context, rates, actor_id),
    do: tenant_call(context, :replace_sales_tax_rates, [rates, actor_id])

  @impl true
  def list_export_settings(context), do: tenant_call(context, :list_export_settings, [])

  @impl true
  def get_export_setting(context, format),
    do: tenant_call(context, :get_export_setting, [format])

  @impl true
  def save_export_setting(context, format, options, actor_id),
    do: tenant_call(context, :save_export_setting, [format, options, actor_id])

  @impl true
  def lines_for_documents(context, ids), do: tenant_call(context, :lines_for_documents, [ids])
end
