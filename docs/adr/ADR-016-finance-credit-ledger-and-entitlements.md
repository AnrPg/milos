# ADR-016: Finance Credit Ledger and Entitlements
Date: 2026-06-11
Status: Accepted

## Context

Phase 8 added manual finance workflows for memberships, packages, payments,
promotions, and referral rewards. Referral rewards could move through
`pending`, `approved`, `applied`, and `rejected`, but an `applied` status alone
did not create financially meaningful state. Admins need a durable record of
credits created by referral rewards, manual adjustments, promotions, reversals,
and future invoice offsets.

The MVP remains manual-payment oriented, but the schema must support later
renewals, invoices, package entitlements, and analytics without breaking
migrations.

## Decision

Finance will own an immutable `finance_credit_ledger_entries` table.

Ledger entries represent credit creation, application, reversal, and future
invoice/payment offsets. Entries are append-only: corrections are represented by
new reversal or application entries rather than updating historical amounts.

Referral reward application creates one idempotent credit grant entry. Admins may
manually apply available credit to a membership payment in MVP by creating a
credit application ledger entry linked to that payment.

Finance read models expose credit entries and calculated credit balances on the
member finance profile. Finance aggregates include granted, applied, and balance
credit values so admin analytics can slice credit exposure with revenue.

## Rationale

Immutable entries provide auditability without introducing a full invoicing
system prematurely. They also allow future invoice offsets, reward reversals,
manual goodwill credits, and promotion-derived credits to share the same
accounting primitive.

Keeping this inside Finance avoids leaking accounting concepts into Identity,
Coaching, or Analytics. Analytics reads materialized totals and emitted events;
Finance remains the source of truth for credit balance semantics.

## Alternatives Considered

Adding a mutable credit balance column to `memberships`:
rejected because it hides history, makes reversals hard to audit, and forces
future migrations when invoices are introduced.

Marking referral rewards as applied without a ledger:
rejected because it cannot distinguish earned, applied, reversed, or remaining
credit.

Creating invoice tables immediately:
rejected because the current product scope is manual payments. A credit ledger
is enough for MVP and remains compatible with later invoices.

## Consequences

Credit balances are computed from ledger entries. Payment application in MVP is
manual and does not mutate the payment amount; it records credit applied against
the payment for reporting and future reconciliation.

The ledger is intentionally append-only at the application/API level. Future
admin correction flows must create reversal entries instead of updating existing
entries.

Referral reward application must be idempotent: repeated status writes must not
create duplicate credit grants for the same reward.

## Implementation Notes

Initial implementation adds the credit ledger schema, store APIs, controller
routes, OpenAPI entries, generated TypeScript schema updates, and admin finance
profile UI. Referral reward application now creates a credit grant entry in the
same transaction as the reward status transition. Admins can apply available
credit to recorded payments manually from the member finance profile.

Referral reward grants are idempotent by ledger `idempotency_key`. The credit is
posted to the reward recipient's active finance membership rather than the
referred membership, because referral reward `membership_id` can describe the
signup being referred while the financial benefit belongs to the referrer.

Finance aggregates now expose granted credit, applied credit, and open credit
balance. The MVP keeps payments immutable; applying credit creates a negative
ledger application linked to the payment and validates both available credit and
remaining payment capacity.

Hardening during implementation also fixed adjacent production issues uncovered
by the full suite: athlete week-view assignment payloads now expose only the
requesting athlete's id, workout completion persists milestone badges with the
correct argument order, streak anchoring uses chronological date comparison
rather than struct term ordering, admin challenge controllers consume validated
JSON body params, and workout completion schedules leaderboard refresh with a
synchronous fallback when Oban is unavailable.
