defmodule Palee.Shop.ShopReportStore do
  @moduledoc "Tenant-scoped facade over the configured ADR-192 shop report store adapter."

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :shop_report_store)

  defp scoped(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, args) end)

  def sales_by_day(context, filters), do: scoped(context, :sales_by_day, [filters])

  def order_groups(context, filters, dimension),
    do: scoped(context, :order_groups, [filters, dimension])

  def line_groups(context, filters), do: scoped(context, :line_groups, [filters])
  def stock(context, filters), do: scoped(context, :stock, [filters])
  def pricing_inputs(context, filters), do: scoped(context, :pricing_inputs, [filters])
  def pricing_targets(context), do: scoped(context, :pricing_targets, [])

  def put_pricing_target(context, category, target_bp, user_id),
    do: scoped(context, :put_pricing_target, [category, target_bp, user_id])

  def reconciliation_figures(context, filters),
    do: scoped(context, :reconciliation_figures, [filters])
end
