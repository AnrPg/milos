# ADR-021: Finance Net Accounting Projections
Date: 2026-06-12
Status: Accepted

## Context

ADR-019 made refunds and credit restoration append-only source facts. The live
invoice/member balance helpers were updated to account for those facts, but the
Finance aggregate materialized view and some dashboard helpers still reported
gross payments and gross credit applications.

This created competing reporting semantics: some admin cards used net
accounting while charts and aggregate slices still counted original facts only.

## Decision

Finance read projections must report net accounting values by default.

Payment revenue facts are gross paid/waived payment amounts minus linked
payment reversal facts. Revenue is attributed to the original payment period for
the existing monthly revenue chart, while a separate refund impact metric may
later report reversal occurrence timing.

Credit analytics must distinguish grants from restorations. Positive
`source_type = "reversal"` ledger entries restore previously applied credit and
must not be counted as newly granted credit. Applied credit totals are net
negative applications minus linked positive restoration entries.

Admin search filtering by Finance dimensions must be evaluated inside the
Finance query boundary before result limiting. Application services may compose
Identity and Finance public read models, but Finance-owned filters cannot be
applied only after a row-limited in-memory merge.

## Rationale

Admins need one consistent interpretation of revenue, credits, and package
filters across cards, charts, queues, and search. Keeping the policy inside
Finance projections avoids duplicate frontend calculations and preserves the
append-only source facts required for auditability.

Attributing payment reversals back to the original payment period keeps the
current monthly revenue chart stable as a restated revenue view. A future cash
movement report can additionally slice refunds by reversal occurrence date.

## Alternatives Considered

Showing gross revenue plus a separate refund line in the current chart:
rejected for MVP because existing admin finance totals are labelled as revenue,
not cash movement. Gross values after refunds are misleading.

Counting credit restoration as credit granted:
rejected because restored credit is not new value issued to the member; it is a
reversal of a prior application.

Loading broader Identity results and filtering in memory:
rejected because it remains pagination-sensitive and cannot guarantee complete
package-filtered search results.

## Consequences

The Finance aggregate materialized view must be recreated when reversal
semantics change. Live Finance summary helpers and aggregate rows must use the
same net formulas.

Admin search remains a PostgreSQL-backed fallback for now, but Finance filters
are pushed to the Finance-owned query boundary before limiting.

## Implementation Notes

Implemented on 2026-06-12.

The Finance aggregate materialized view is recreated by
`20260612170000_make_finance_aggregates_reversal_aware.exs`. Paid revenue now
uses original paid payment rows minus linked `finance_payment_reversals`,
attributed to the original payment month. Credit aggregate facts no longer
count `source_type = "reversal"` rows as new credit grants, and net applied
credit subtracts restoration rows from original applications.

Live Finance summary helpers were aligned with the same semantics:
`paid_revenue_cents` now filters by original payment date and subtracts
reversals for those payments, while `invoice_credit_offset_cents` reports net
invoice offsets after credit restoration.

Admin search now passes package code/family filters into
`Finance.search_member_summaries/1`, and the Ecto query applies those filters
before ordering/limiting membership summaries. The application service still
composes Identity results with Finance public summaries, but Finance-owned
facets are no longer applied only after a limited in-memory merge.

The referral event form now labels referred membership as required and disables
submission until the membership-backed conversion fields are present.

Verification completed:

- `MIX_BUILD_PATH=/tmp/milos-api-build-dev DB_PORT=5434 mix ecto.migrate`
- `MIX_BUILD_PATH=/tmp/milos-api-build-test DB_PORT=5434 mix test test/milos_training/finance/finance_test.exs test/milos_training/application/admin_search_users_test.exs`
- `MIX_BUILD_PATH=/tmp/milos-api-build-dev mix compile --warnings-as-errors`
- `MIX_BUILD_PATH=/tmp/milos-api-build-test DB_PORT=5434 mix test`
- `npx eslint src/components/admin-finance.tsx`
- `npx tsc --noEmit`
- `npm run build`

The full API suite passed with 228 tests and 0 failures. Frontend ESLint,
TypeScript, and production Next.js build passed. The remaining async SQL
sandbox and notification/Oban warnings are pre-existing test-harness noise
tracked in the technical debt ledger.
