# Shop Revenue Reconciliation Runbook

ADR-192 §5. Shop sales are their own revenue stream (`revenue_stream = 'shop'`,
ADR-190), and each sale is written to three places. This check proves those
three places agree to the cent for every business day.

## What is compared

For every gym-local business day (organization time zone, ADR-176) and
currency, three integer-cent figures are computed:

| Figure | Source | Day it belongs to |
|---|---|---|
| `orders_cents` | `shop_orders.total_cents - refunded_cents` for paid, partially refunded and refunded orders | the order's `paid_at`, converted to the gym's local date |
| `invoice_lines_cents` | `finance_invoice_lines` with `revenue_stream = 'shop'` on invoices that are neither deleted nor void, minus the shop-stream reversals of that invoice's payments | the paid day of the order the line came from (`source_type`/`source_id`) |
| `payments_cents` | `membership_payments` with `revenue_stream = 'shop'` and status `paid` or `refunded`, minus their shop-stream reversals | the payment's `paid_on` |

A day is **ok** when all three are equal. `drift_cents` is the largest minus
the smallest of the three. Refunds are attributed to the **sale** day, so a
refund issued on Tuesday for a Saturday sale changes Saturday's figures; this
is why the nightly run looks back over a week.

No floats are involved: amounts are summed as integers in PostgreSQL and
compared in the pure `Palee.Shop.Domain.RevenueReconciliation` module.

## When it runs

- **Nightly:** `Palee.Workers.ShopRevenueReconciliationJob` (Oban `analytics`
  queue, cron `25 3 * * *` UTC) checks every active business for the last 7
  business days ending yesterday. A failure for one business is logged and
  does not stop the others.
- **On demand:** `GET /api/org/<slug>/admin/shop/reports/reconciliation?days=7` (or
  `?from=YYYY-MM-DD&to=YYYY-MM-DD`, at most 366 days). It needs
  `view_business_analytics`, `view_finance_reports` or `manage_shop`. The
  on-demand run returns the per-day figures and does not emit metrics or
  logs.
- **Tests:** `Palee.Application.ReconcileShopRevenue.call/4` is used directly
  in `test/palee/shop/shop_reports_test.exs`.

## Signals

- Telemetry `[:palee, :shop, :reconciliation, :checked]` with `days`,
  `drifted_days` and `drift_cents`, and the metadata `result` (`ok` or
  `drift`).
- Prometheus:
  - `palee_shop_reconciliation_runs_total{result}`
  - `palee_shop_reconciliation_drifted_days_total`
  - `palee_shop_reconciliation_drift_cents` (last value)
- Alert `PaleeShopRevenueDrift` (warning): any drifted day reported in the
  last 26h.
- Logs: one `shop_revenue_drift` warning per drifting day, with the fields
  `organization_id`, `day`, `currency`, `orders_cents`,
  `invoice_lines_cents`, `payments_cents` and `drift_cents`.

## Investigating drift

1. Find the log lines: search for `shop_revenue_drift` and note the
   organization, the day and which figure differs from the other two.
2. Re-run on demand for that day to see whether it still drifts (the
   mismatch may have been a sale that was still in progress at 03:25):
   `GET /api/org/<slug>/admin/shop/reports/reconciliation?from=<day>&to=<day>` as an
   admin of that business.
3. Read the pattern:
   - **orders differ, lines = payments:** an order's `total_cents` or
     `refunded_cents` was changed without a matching Finance write. Look for
     order updates outside `Palee.Application.Shop.*` use cases.
   - **lines differ:** an invoice was voided, deleted or edited by hand, or
     a line lost its `source_type = 'shop_order_line'` lineage.
   - **payments differ:** a payment or reversal was recorded with the wrong
     stream or amount, or deleted. Reversals inherit stream and source from
     their payment through a trigger, so a mismatch here usually means a
     soft-deleted payment.
   - **different currency rows:** an order and its payment were written in
     different currencies.
4. List the day's rows (as the migration owner, in the gym's zone):

   ```sql
   SELECT id, total_cents, refunded_cents, payment_status, paid_at
   FROM shop_orders
   WHERE organization_id = :org
     AND ((paid_at AT TIME ZONE 'UTC') AT TIME ZONE :zone)::date = :day;
   ```

   then follow `membership_payments.source_id` and
   `finance_invoice_lines.source_id` back to the orders.
5. Fix the data through the application (a refund or a correcting invoice),
   never by editing ledger rows: stock movements and price changes are
   append-only, and finance documents must keep their audit trail. The next
   nightly run clears the alert once the day reconciles.

## Known limits

- The check covers the shop stream only. Membership, package and event
  revenue are not reconciled here.
- Online card payment is not available in the MVP (payments use the mock
  adapter), so there is no payment-provider settlement to compare against
  yet. When a real provider arrives, add its settlement as a fourth figure.
