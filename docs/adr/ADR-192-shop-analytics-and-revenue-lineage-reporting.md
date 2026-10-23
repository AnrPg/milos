# ADR-192: Shop analytics, revenue by stream and revenue lineage reporting
Date: 2026-10-23
Status: Accepted

## Context
ADR-190 adds an e-shop to Palee: a catalog with variants, an inventory
ledger, orders placed online for pickup or at the desk (POS), and invoice
lines and payments that carry a `revenue_stream` of `shop` plus a reference
to the order they come from. The owner asked that shop sales "count towards
analytics (have their own reports even) and financials with a distinct
lineage and observability".

What existed before this decision:

- **Finance summary** (`GET /admin/finance/summary`,
  `EctoFinanceStore.financial_summary/1`): `totals.paid_revenue_cents` is the
  sum over paid, non-deleted `membership_payments` with `paid_on` in the
  window, each net of its own reversals (`GREATEST(amount - reversed, 0)`).
  `monthly_revenue` comes from the `finance_aggregates` view, or from the
  payments themselves under a branch filter. Nothing tells a membership
  payment from a class pack, an event ticket (ADR-153 receipts) or a product.
- **Business analytics** (`GET /admin/analytics/summary`) reuses the finance
  summary for its revenue tile.
- **Events console «Αναλυτικά»** (ADR-185) reports reach, RSVPs, attendance
  and conversion per event; «Οικονομικά» reports ticket income per event.
  Neither is a revenue report of the business.
- **Accounting export** (ADR-126): versioned CSV/JSON datasets (payments,
  allocations, reversals, credits, refund receipts), schema version 1.
- **Observability** (ADR-116): `PaleeWeb.Telemetry.prometheus_metrics/0`
  feeds an in-house Prometheus exporter behind `METRICS_PORT`;
  `TelemetryLogReporter` writes a one-minute `telemetry_summary=` log line;
  alert rules live in `ops/observability/prometheus/rules`. Labels must be
  bounded (no tenant or entity ids).

Branch filters (ADR-186 §7) narrow reports to the people whose home branch
is in the filter, or to facts that carry a branch. Business days follow the
gym's zone (ADR-176, ADR-179 `GymClock`).

## Decision

### 1. One closed list of revenue streams, refined in the domain
ADR-190 owns the stored column (`revenue_stream`, default `membership`, so
every pre-existing row reads `membership`) and its key list
(`Palee.Finance.Domain.RevenueStream`). Reports refine the stored default
through the pure `Palee.Finance.Domain.RevenueBreakdown`, whose `classify/1`
decides the reporting stream of one payment fact in this order:

1. an explicit stored stream other than the default wins (ADR-190 writes
   `shop`; any future writer sets its own);
2. the package type of the subscription the payment is for: recurring types
   (`membership`, `shared`, `corporate`) are `membership`; one-off types
   (`class_pack`, `drop_in`, `trial`, `pt_pack`, `add_on`) are `package`;
3. an event receipt (ADR-153: idempotency key `community_event_attendee:…`,
   or an `event` line on its invoice) is `event`;
4. everything else (manual receipts, adjustments) is `other`.

The refinement is computed at read time and never back-filled, so no stored
value is rewritten and a misclassification is a code fix, not a data
migration.

### 2. Finance totals gain a breakdown; existing numbers stay identical
`financial_summary/1` adds, next to the unchanged keys:

- `totals.revenue_by_stream`: `%{stream => net_cents}` for every stream (zeros
  included);
- `revenue_streams`: one row per stream with `gross_cents`, `refunded_cents`,
  `net_cents` and `payment_count`;
- `monthly_revenue_by_stream`: the same split per month (24 months).

All are computed from **the same payment set, window, branch filter and
per-payment reversal netting** as `paid_revenue_cents`, so
`Σ revenue_by_stream == paid_revenue_cents` holds by construction (and is
asserted in tests). Refunds net out within the stream of the payment they
reverse. Branch splits (`branches[]`) and the analytics dashboard carry their
own `revenue_by_stream`.

Under a branch filter, shop payments follow the **order's** branch
(`shop_orders.pickup_location_id`, the desk branch for POS sales), because a
walk-in sale has no member and therefore no home branch; every other stream
keeps following people (ADR-186). Pre-ADR-190 rows are all `membership`, so
their filtering is unchanged.

### 3. Exports carry the lineage
The accounting export's `payments` and `reversals` datasets gain four
trailing columns (existing columns keep their order) and the schema version
becomes 2:

- `revenue_stream`: the stored ADR-190 value;
- `report_stream`: the refined stream of §1 (what the finance page shows);
- `source_type` / `source_id`: the originating fact (`shop_order`, …) when
  known.

Walk-in shop payments (no membership) are exported too.

### 4. Shop reports have their own read model and endpoints
`Palee.Application.ShopReports` (facade) builds every report from the shop
facts of ADR-190 through a tenant-scoped `Palee.Shop.ShopReportStore` (port
`Palee.Shop.Ports.ShopReportStore`, adapter
`Palee.Infrastructure.Shop.EctoShopReportStore`, RepoContext.run, registered
in the architecture task) and the pure `Palee.Shop.Domain.SalesReport` and
`Palee.Shop.Domain.PricingIndicators` maths. The adapter aggregates in
PostgreSQL (`GROUP BY` over indexed `paid_at` ranges); the domain only
shapes the groups. Endpoints under `/api/org/:slug/admin/shop/…`, shaped for
a future «Κατάστημα › Αναλυτικά» tab:

| Path | Report |
|---|---|
| `reports/overview` | the headline KPIs of the window |
| `reports/sales` | per gym-local day: gross, refunds, net, orders, AOV; plus totals |
| `reports/products` | top products and variants by revenue and by units |
| `reports/margin` | revenue, cost and margin where cost price is known (coverage shown) |
| `reports/channels` | by channel (online pickup vs POS desk) and by branch |
| `reports/inventory` | stock on hand, stock value at cost, low stock, sell-through |
| `reports/attribution` | sales by promotion code, campaign and source (feed post …) |
| `reports/pricing` | the pricing indicators of §6 per variant |
| `reports/reconciliation` | the §5 check on demand |
| `pricing-targets` (GET, PUT) | target margin per category (§6) |

Reports take `days` (1–366, default 30) or `from`/`to` (at most 366 days)
and `location_ids`. Shop facts carry a branch, so the filter applies to the
branch of the order or stock, not to home branches. Days are bucketed in the
gym's zone (`(paid_at AT TIME ZONE 'UTC') AT TIME ZONE zone`). Reads need
`view_business_analytics` or `manage_shop` (any of them, ADR-099); the
reconciliation also accepts `view_finance_reports`; writing targets needs
`manage_shop` or `manage_settings`.

### 5. Observability: shop metrics, revenue counters and a reconciliation
- The shop's ADR-190 telemetry (`[:palee, :shop, :order, *]`,
  `[:palee, :shop, :stock, :moved | :status_changed]`,
  `[:palee, :shop, :variant, :price_changed]`) becomes Prometheus counters.
  Its metadata carries tenant and entity ids, so the metrics fold labels to
  closed lists (`channel`, `payment_mode`, `kind`, `status`).
- Finance emits `[:palee, :finance, :revenue, :recorded | :refunded]` with a
  `stream` label from `RecordPayment` and `ReversePayment`; shop payments
  reach the same counters through `RevenueStreamBridge`, which listens to the
  shop's paid and refunded events. All of them join the one-minute log
  summary.
- `Palee.Application.ReconcileShopRevenue` compares, per gym-local day and
  currency, shop order totals, shop-stream invoice lines and shop payments
  minus refunds, in integer cents. It emits
  `[:palee, :shop, :reconciliation, :checked]`, logs one
  `shop_revenue_drift` warning per drifting day, and drives the
  `PaleeShopRevenueDrift` alert. A nightly Oban job runs it for every active
  business over the last 7 days (a refund changes its sale's day).
- The runbook is `docs/operations/shop-revenue-reconciliation.md`.

### 6. Pricing indicators (advisory)
Per variant, from the sales window (default 90 days) and an append-only
**price ledger** (`shop_variant_price_changes`, written by a trigger on
`shop_variants` whenever `price_cents` or `cost_price_cents` change, seeded
with an `opening` row per existing variant):

- margin % and markup % from cost; sell-through %; velocity (units per week,
  over the days the variant was actually on sale) and days of stock left;
- velocity before and after each price change (periods shorter than 7 days
  are not compared);
- discount depth and its effect on volume (promotion-code or discounted
  lines vs full price);
- a log-log price-elasticity estimate when at least two price points exist,
  with R² and a confidence (`none | low | medium | high`);
- price bands per category (p25, median, p75 of current prices) and the
  variant's position against similar items of the same business;
- a **suggested price range**: cost-plus at the category's target margin
  (`shop_pricing_targets`, default 40%), widened up for fast movers, down
  (never below cost) for slow movers, and narrowed when demand looks elastic.
  It returns its inputs and an explanation and never changes a price.

All maths is integer cents and basis points with half-up rounding; only the
elasticity fit uses floats, and it never feeds a money figure directly.

## Rationale
- Deriving the stream keeps old totals byte-for-byte identical, which the
  owner required, and avoids a risky back-fill over every payment.
- Computing the breakdown from the same query as the headline figure makes
  the invariant structural rather than hoped for.
- A separate shop read model keeps order-level analytics (AOV, units,
  margin, stock) out of the finance ledger, which knows payments, not
  baskets; the finance breakdown answers "how much money", the shop reports
  answer "what sold".

## Alternatives Considered
- **Store `revenue_stream` on every payment and back-fill history.** Exact,
  but rewrites history, needs a migration across all tenants and still needs
  the same classifier to back-fill. Rejected for now; the explicit column of
  ADR-190 is honoured first, so new writers converge on it.
- **Extend the `finance_aggregates` materialized view with a stream
  dimension.** Faster monthly reads, but a view change for every stream rule
  and a refresh lag on a figure owners compare against the till. Kept as a
  follow-up if the summary gets slow.
- **A separate shop revenue figure outside finance.** Would make shop money
  invisible to the finance page and accountants. Rejected by the owner's
  brief.
- **Per-tenant Prometheus labels.** Unbounded cardinality; per-business
  numbers belong in the reports, not in metrics.

## Consequences
- Accounting export consumers see schema version 2 with four new trailing
  columns; readers that select by column name are unaffected.
- A new revenue writer must set an explicit stream or teach `RevenueBreakdown`
  how to recognise it; otherwise its money lands in `other`.
- The reconciliation depends on ADR-190 writing one shop invoice line per
  order and linking payments and refunds to the order; any change there must
  keep the check passing.
- UI for «Κατάστημα › Αναλυτικά» is pending the owner's approval of the
  mockups; the endpoints exist ahead of it.

## Implementation Notes
- Domain (pure): `Palee.Finance.Domain.RevenueBreakdown`,
  `Palee.Shop.Domain.SalesReport`, `Palee.Shop.Domain.PricingIndicators`,
  `Palee.Shop.Domain.RevenueReconciliation`.
- Application: `Palee.Application.ShopReports`,
  `Palee.Application.ReconcileShopRevenue`, `BranchReport.split_params/3`;
  `GetAdminFinanceSummary` and `GetAdminAnalyticsSummary` pass the breakdown
  through.
- Infrastructure: `EctoFinanceStore` (breakdown on the shared base query,
  schemaless reads of the lineage columns), `EctoFinanceAccountingStore`
  (export v2), `EctoShopReportStore` (raw SQL; every parameter typed and an
  explicit `organization_id = $1` on top of RLS),
  `Observability.RevenueStreamBridge`, `Palee.Finance.RevenueTelemetry`,
  `Palee.Workers.ShopRevenueReconciliationJob` (cron `25 3 * * *`).
- Web: `AdminShopReportController`, `PaleeWeb.Schemas.ShopReports`
  (OpenAPI), routes and `RouteCapabilities`; `FallbackController` maps
  `:invalid_report_window` and `:invalid_pricing_target` to 422.
- Migration `20261213000000_shop_pricing_ledger_and_report_indexes`:
  `shop_variant_price_changes` (append-only, tenant trigger, forced RLS),
  `shop_pricing_targets` (unique per category, `NULLS NOT DISTINCT` for the
  default), `shop_orders (organization_id, paid_at) WHERE paid_at IS NOT
  NULL` and `membership_payments (organization_id, revenue_stream, paid_on)`
  for paid, non-deleted rows. Both tables are classified in
  `Tenancy.Audit` and the shop `TenantDataPolicy`.
- Metrics: `palee_revenue_{recorded,refunded}_cents_total{stream,currency}`,
  `palee_revenue_{payments,refunds}_total{stream}`,
  `palee_shop_orders_{placed,paid,ready,picked_up,cancelled,refunded}_total{channel}`,
  `palee_shop_paid_cents_total{channel,payment_mode}`,
  `palee_shop_refunded_cents_total{channel}`,
  `palee_shop_stock_movements_total{kind}`,
  `palee_shop_stock_units_moved_total{kind}`,
  `palee_shop_low_stock_alerts_total{status}`,
  `palee_shop_price_changes_total`,
  `palee_shop_reconciliation_runs_total{result}`,
  `palee_shop_reconciliation_drifted_days_total`,
  `palee_shop_reconciliation_drift_cents`. Counters are event-level: a
  process restart resets them, and per-business figures live in the reports.
- Tests: domain tests for each pure module, `test/palee/shop/shop_reports_test.exs`
  (time-zone bucketing, branch filter, ledger, reconciliation through the
  real ADR-190 desk sale and refund writers, export lineage, the finance
  invariant), the controller test and the telemetry test; the promtool case
  for `PaleeShopRevenueDrift` is in `ops/observability/prometheus/tests`.
- Payments use the mock adapter in the MVP; online card payment is not
  available, so there is no provider settlement to reconcile yet.
