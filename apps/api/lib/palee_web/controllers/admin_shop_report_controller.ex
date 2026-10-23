defmodule PaleeWeb.AdminShopReportController do
  @moduledoc """
  ADR-192: the shop's reports, pricing indicators and revenue
  reconciliation, for a future «Κατάστημα › Αναλυτικά» tab. Thin: every
  action calls one application facade.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{ReconcileShopRevenue, ShopReports}
  alias PaleeWeb.Schemas.ShopReports, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Shop Reports"])
  security([%{"bearerAuth" => []}])

  @window S.parameters()

  operation(:overview,
    summary: "Shop KPIs: net sales, orders, AOV, units, refunds, margin and stock",
    parameters: @window,
    responses: [ok: {"Shop KPIs", "application/json", S.overview_response()}]
  )

  def overview(conn, params), do: reply(conn, ShopReports.overview(context(conn), params))

  operation(:sales,
    summary: "Shop sales per gym-local day: gross, refunds, net, orders and AOV",
    parameters: @window,
    responses: [ok: {"Shop sales", "application/json", S.sales_response()}]
  )

  def sales(conn, params), do: reply(conn, ShopReports.sales(context(conn), params))

  operation(:products,
    summary: "Top shop products and variants by revenue and by units",
    parameters: @window ++ [S.limit_parameter()],
    responses: [ok: {"Top products", "application/json", S.products_response()}]
  )

  def products(conn, params), do: reply(conn, ShopReports.products(context(conn), params))

  operation(:margin,
    summary: "Shop revenue, cost and margin where the cost price is known",
    parameters: @window,
    responses: [ok: {"Margin", "application/json", S.margin_response()}]
  )

  def margin(conn, params), do: reply(conn, ShopReports.margin(context(conn), params))

  operation(:channels,
    summary: "Shop sales by channel (online pickup or desk) and by branch",
    parameters: @window,
    responses: [ok: {"Channels", "application/json", S.channels_response()}]
  )

  def channels(conn, params), do: reply(conn, ShopReports.channels(context(conn), params))

  operation(:inventory,
    summary: "Stock on hand, stock value, low stock and sell-through",
    parameters: @window,
    responses: [ok: {"Inventory", "application/json", S.inventory_response()}]
  )

  def inventory(conn, params), do: reply(conn, ShopReports.inventory(context(conn), params))

  operation(:attribution,
    summary: "Shop sales by promotion code, campaign and source (feed post, public page...)",
    parameters: @window,
    responses: [ok: {"Attribution", "application/json", S.attribution_response()}]
  )

  def attribution(conn, params), do: reply(conn, ShopReports.attribution(context(conn), params))

  operation(:pricing,
    summary: "Advisory pricing indicators per variant (default window 90 days)",
    parameters: @window,
    responses: [ok: {"Pricing indicators", "application/json", S.pricing_response()}]
  )

  def pricing(conn, params), do: reply(conn, ShopReports.pricing(context(conn), params))

  operation(:pricing_targets,
    summary: "Target margin per product category (cost-plus input)",
    responses: [ok: {"Pricing targets", "application/json", S.pricing_targets_response()}]
  )

  def pricing_targets(conn, _params), do: reply(conn, ShopReports.pricing_targets(context(conn)))

  operation(:put_pricing_target,
    summary: "Set or clear the target margin of a category (or the default)",
    request_body: {"Pricing target", "application/json", S.pricing_target_request()},
    responses: [ok: {"Pricing targets", "application/json", S.pricing_targets_response()}]
  )

  def put_pricing_target(conn, _params),
    do: reply(conn, ShopReports.put_pricing_target(context(conn), conn.body_params))

  operation(:reconciliation,
    summary: "Shop revenue reconciliation: orders == shop invoice lines == payments - refunds",
    parameters: Enum.reject(@window, &(&1.name == :location_ids)),
    responses: [ok: {"Reconciliation", "application/json", S.reconciliation_response()}]
  )

  def reconciliation(conn, params),
    do: reply(conn, ReconcileShopRevenue.on_demand(context(conn), params))

  defp context(conn), do: conn.assigns.tenant_context

  defp reply(conn, {:ok, payload}), do: json(conn, payload)
  defp reply(_conn, error), do: error
end
