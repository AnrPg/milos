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

### 1. One closed list of revenue streams, classified in the domain
`Palee.Finance.Domain.RevenueStream` (pure) owns the list
`membership | package | event | shop | other` and `classify/1`, which
decides the stream of one payment fact in this order:

1. an explicit stream on the payment or its invoice lines (ADR-190 writes
   `shop`; any future writer sets its own);
2. the package type of the subscription the payment is for: recurring types
   (`membership`, `shared`, `corporate`) are `membership`; one-off types
   (`class_pack`, `drop_in`, `trial`, `pt_pack`, `add_on`) are `package`;
3. an event receipt (ADR-153: idempotency key `community_event_attendee:…`,
   or an `event` charge category on its lines) is `event`;
4. everything else (manual receipts, adjustments) is `other`.

The stream is derived at read time, never back-filled into old rows, so no
historical figure is rewritten and a misclassification is a code fix, not a
data migration.

### 2. Finance totals gain a breakdown; existing numbers stay identical
`financial_summary/1` adds, next to the unchanged keys:

- `totals.revenue_by_stream`: `%{stream => net_cents}` for every stream (zeros
  included);
- `revenue_streams`: one row per stream with `gross_cents`, `refunded_cents`,
  `net_cents` and `payment_count`.

Both are computed from **the same payment set, window, branch filter and
per-payment reversal netting** as `paid_revenue_cents`, so
`Σ revenue_by_stream == paid_revenue_cents` holds by construction (and is
asserted in tests). Refunds net out within the stream of the payment they
reverse. Branch splits (`branches[]`) carry their own `revenue_by_stream`.

### 3. Exports carry the lineage
The accounting export's `payments` and `reversals` datasets gain
`revenue_stream`, `source_type` and `source_id` columns, appended at the end
(existing columns keep their order), and the schema version becomes 2.
`source_type`/`source_id` name the originating fact (`shop_order`, a
subscription, an event attendee) when known.

### 4. Shop reports have their own read model and endpoints
`Palee.Application.ShopReports` (facade) builds every report from the shop
facts of ADR-190 through a tenant-scoped `ShopReportStore` (RepoContext.run,
registered in the architecture task) and pure
`Palee.Shop.Domain.SalesReport` maths. Endpoints under
`/api/org/:slug/admin/shop/reports/*`, shaped for a future «Κατάστημα ›
Αναλυτικά» tab:

| Path | Report |
|---|---|
| `sales` | per gym-local day: gross, refunds, net, orders, AOV; plus totals |
| `products` | top products and variants by revenue and by units |
| `margin` | revenue, cost and margin where cost price is known (coverage shown) |
| `channels` | by channel (online pickup vs POS desk) and by branch |
| `inventory` | stock on hand, stock value, low-stock list, sell-through |
| `attribution` | sales by promotion code / campaign / source (feed post …) |

All take `days` (or `from`/`to`) and `location_ids`. Shop facts carry a
branch, so the filter applies to the branch of the order or stock, not to
home branches. Days are bucketed in the gym's zone. Access: the existing
`view_business_analytics` capability, or the shop's own management
capability (any of them, per ADR-099).

### 5. Observability: shop telemetry, revenue counters and a reconciliation
- Shop telemetry events become Prometheus metrics with bounded labels
  (`channel`, `stream`, `reason`): orders placed, paid and refunded, revenue
  cents by stream, stock movements by kind and low-stock alerts. They also
  join the one-minute log summary.
- `Palee.Application.ReconcileShopRevenue` compares, per gym-local day,
  shop order totals, shop-stream invoice lines and shop payments minus
  refunds. Drift emits `[:palee, :shop, :reconciliation]` (a gauge and a
  drift counter), a structured warning log, and fires the
  `PaleeShopRevenueDrift` alert. A nightly Oban job runs it for every active
  business for yesterday; tests call it directly.
- The runbook is `docs/operations/shop-revenue-reconciliation.md`.

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
- Accounting export consumers see schema version 2 with three new trailing
  columns; readers that select by column name are unaffected.
- A new revenue writer must set an explicit stream or teach `RevenueStream`
  how to recognise it; otherwise its money lands in `other`.
- The reconciliation depends on ADR-190 writing one shop invoice line per
  order and linking payments and refunds to the order; any change there must
  keep the check passing.
- UI for «Κατάστημα › Αναλυτικά» is pending the owner's approval of the
  mockups; the endpoints exist ahead of it.

## Implementation Notes
(Filled in during implementation.)
