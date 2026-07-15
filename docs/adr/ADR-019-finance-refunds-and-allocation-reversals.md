# ADR-019: Finance Refunds and Allocation Reversals
Date: 2026-06-12
Status: Accepted

## Context

Finance invoices, payments, and credit offsets are now the accounting source of
truth for member balances and entitlement. Allocated invoices cannot currently
be voided because payments and credit offsets have no audited reversal path.

Admins need production-safe correction workflows for mistakes, refunds,
chargebacks, and goodwill reversals without mutating historical payment rows or
deleting credit-ledger entries.

## Decision

Finance will model payment refunds/reversals as append-only
`finance_payment_reversals` records linked to the original payment, membership,
user, and invoice when applicable.

Credit applications will be reversed by creating a positive
`finance_credit_ledger_entries` row with `source_type = "reversal"` and
`entry_type = "reversal"`, linked to the same invoice/payment as the original
negative application and carrying the original ledger entry id in `params`.

Invoice balances will be derived from:

- original paid/waived payments minus payment reversals
- original negative credit applications minus positive credit reversals

Original payments and credit application rows remain immutable facts.

## Rationale

Append-only reversal facts preserve auditability and avoid hidden mutation of
financial history. This matches the existing credit-ledger approach and keeps
future invoice exports, receipts, and provider reconciliation additive.

Keeping payment reversal records separate from credit ledger entries avoids
mixing cash movement with member credit balance movement. Credit reversal
entries restore member credit balances; payment reversal records reduce applied
cash against invoices.

## Alternatives Considered

Mutating payment status to `refunded`:
rejected because it destroys partial refund information and hides the timing
and reason for the correction.

Deleting or editing credit application entries:
rejected because the credit ledger is intentionally immutable.

Creating negative payment rows:
rejected because it overloads `membership_payments`, complicates existing
payment-status semantics, and makes original payment allocation harder to audit.

## Consequences

Invoice balance queries must account for reversal facts. Admin UI can offer
refund/reverse actions without enabling destructive invoice edits.

Void remains blocked while any net payment or net credit allocation remains.
Once allocations are fully reversed, the existing void flow can void the
invoice.

## Implementation Notes

Implemented as an additive Phase 8 hardening pass.

Payment reversals are stored in `finance_payment_reversals` with immutable
links to the original payment, member, user, and invoice. Invoice paid totals,
member payment history, finance summary revenue, and void eligibility now use
net payment amounts after reversal records.

Credit application reversals are stored as positive
`finance_credit_ledger_entries` with `source_type = "reversal"`,
`entry_type = "reversal"`, and `reversed_credit_ledger_entry_id` pointing to
the original negative application/offset. Member credit balances, invoice
credit-applied totals, and admin profile UI now use remaining reversible credit
amounts instead of raw historical application amounts.

Admin APIs and UI were added for refund/payment reversal and applied-credit
restoration. The UI uses per-request UUIDs for idempotency, hides fully restored
credit entries, and defaults reversal amounts to the remaining reversible
balance while backend domain rules remain authoritative.

Deferred follow-up: external payment-provider reconciliation, refund receipts,
and accounting exports are still out of scope for the current self-hosted,
manual-payment MVP.
