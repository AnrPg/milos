defmodule Palee.Finance.RevenueStreamStore do
  @moduledoc false
  @behaviour Palee.Finance.Ports.RevenueStreamStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :finance_revenue_stream_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def record_invoice(context, attrs), do: tenant_call(context, :record_invoice, [attrs])
  @impl true
  def record_payment(context, attrs), do: tenant_call(context, :record_payment, [attrs])
  @impl true
  def record_sale(context, attrs), do: tenant_call(context, :record_sale, [attrs])
  @impl true
  def reverse_payment(context, attrs), do: tenant_call(context, :reverse_payment, [attrs])
  @impl true
  def void_invoice(context, invoice_id, attrs),
    do: tenant_call(context, :void_invoice, [invoice_id, attrs])

  @impl true
  def set_fiscal_receipt_ref(context, invoice_id, ref),
    do: tenant_call(context, :set_fiscal_receipt_ref, [invoice_id, ref])

  @impl true
  def stream_rows(context, from, to, filters),
    do: tenant_call(context, :stream_rows, [from, to, filters])

  @impl true
  def lineage(context, source_type, source_id),
    do: tenant_call(context, :lineage, [source_type, source_id])

  @impl true
  def list_for_user(context, stream, user_id),
    do: tenant_call(context, :list_for_user, [stream, user_id])
end
