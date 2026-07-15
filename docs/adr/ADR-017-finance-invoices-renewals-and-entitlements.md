# ADR-017: Finance Invoices, Renewals, and Entitlements
Date: 2026-06-12
Status: Accepted

## Context

Phase 8 established Finance as a bounded context with memberships, packages,
manual payments, promotions, referrals, credit ledger entries, and finance
aggregates. Credits are now durable, but there is still no source-of-truth
receivable record that can connect package renewal, payment allocation, credit
offsets, overdue balances, and entitlement state.

The product needs production-usable finance management without adding an
external payment processor yet. The schema must remain compatible with later
automated renewals, receipts, reminders, Stripe/bank integrations, and package
entitlement enforcement.

## Decision

Finance will own `finance_invoices` and `finance_invoice_lines`.

Invoices represent the receivable for a membership billing period or manual
charge. Invoice lines snapshot the package/subscription/service being charged.
Invoice status is derived or updated inside Finance using the lifecycle:
`draft`, `issued`, `partially_paid`, `paid`, `overdue`, and `void`.

Manual payments may be linked to invoices. Credit ledger entries may be linked
to invoices and invoice lines for invoice offsets. Invoice balances are computed
from invoice totals minus linked paid/waived payments and linked credit
applications.

Membership entitlement is exposed as a Finance read model derived from
membership status, package subscription status, invoice status, due dates,
balance due, and credit balance. The MVP stores entitlement snapshots on
memberships for operational filtering while keeping invoice/payment/credit facts
as the accounting source of truth.

## Rationale

Invoices are the missing financial primitive between packages and money
movement. They make revenue, overdue balances, renewals, and credit application
auditable without prematurely integrating a payment gateway.

Keeping invoices in Finance preserves bounded-context ownership. Identity only
owns users; Scheduling and Workouts can later consume public Finance entitlement
APIs without importing finance schemas.

Deriving balances from append-only payments and ledger entries prevents hidden
balance mutation and supports future reversals, refunds, invoice adjustments,
and accounting exports.

## Alternatives Considered

Continuing with manual payments only:
rejected because payments do not describe what was owed, due, overdue, or
renewed. Entitlement would remain hand-maintained and analytics would lack
outstanding balance.

Adding a mutable `balance_due_cents` column only:
rejected because it hides invoice history and makes audits/reversals fragile.

Integrating Stripe before invoices:
rejected because the app needs a self-hosted internal source of truth first.
External payment providers can later create payments against invoices.

## Consequences

Finance APIs must create and issue invoices before payment/credit application
can become financially complete.

The MVP can generate renewal invoices manually from the active package
subscription. Automated scheduled renewal jobs, email/SMS reminders, invoice
PDFs, and external payment collection remain additive future work.

Entitlement enforcement in Scheduling and Execution calls the public Finance
API through an Application Service. It does not import Finance schemas across
context boundaries. During the additive rollout, users without a Finance
membership remain unmanaged.

## Implementation Notes

The invoice vertical slice is exposed end to end through application services,
OpenAPI-backed admin routes, regenerated TypeScript contract artifacts, frontend
finance API helpers, and the admin member finance profile. Admins can create
manual invoices, generate renewals, issue or void eligible invoices, record
invoice payments, and apply membership credit.

Invoice allocation rules are explicit pure domain policy. Payments and credits
are accepted only for issued, partially paid, or overdue invoices, cannot exceed
the remaining balance, and cannot be added after payment or voiding. Draft
invoices cannot receive financial allocations.

Voiding is intentionally rejected when an invoice already has paid/waived
payments or credit offsets. This preserves the audit trail until a dedicated
refund, reversal, or credit-restoration workflow is implemented instead of
silently detaching or erasing allocations.

Every invoice line subscription link is validated against the invoice
membership. Renewal invoices are idempotent for membership, package
subscription, and service period through both an application lookup and a
partial unique PostgreSQL index for non-void renewal invoices. Calendar month,
quarter, and year periods preserve month-end semantics; custom billing periods
require an explicit valid end date.

Membership entitlement snapshots are refreshed transactionally after
membership updates, package assignment, invoice issue/status changes, payments,
credit applications, and eligible voids. Finance profile reads also refresh the
snapshot to account for date-based expiry. Scheduling booking and workout
execution enforce entitlement through a cross-context application service using
the Finance public query and pure entitlement policy. Users without a Finance
membership remain unmanaged during the additive rollout; active and grace
memberships are allowed, while blocked and inactive memberships are rejected.

Finance summary analytics now expose outstanding invoice balance, overdue
balance, renewal conversion, and invoice credit-offset impact. The admin
dashboard surfaces these metrics alongside overdue invoice queues.

Validation completed with 202 backend tests, 0 failures; a production Next.js
build; full frontend ESLint; TypeScript checks; regenerated OpenAPI and
TypeScript schemas; and focused finance/entitlement regression suites. Live HTTP
verification against local PostgreSQL and Redis created a member, assigned a
package, created and issued an invoice, rejected draft payment and overpayment,
accepted exact payment, rejected voiding the allocated invoice, and returned a
paid invoice with an active persisted entitlement.
