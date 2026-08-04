# ADR-084: Finance correction and soft-delete policy
Date: 2026-08-04
Status: Accepted

## Context

Receipt mode reuses the invoice and payment ledger. A reversed receipt therefore
re-enters the generic invoice lifecycle and can be labelled `overdue` merely
because its receipt-date surrogate is in the past. This misstates a synchronous
cash transaction as an unpaid receivable.

Admins also need a safe, guided way to remove accidental or exploratory
financial records from operational views. The source facts must remain in the
database for recovery and traceability.

## Decision

Receipts retain their invoice/payment backing facts but are presented with a
receipt-specific corrected state after a full payment reversal; they are never
overdue and do not contribute to overdue entitlement blocking.

The Finance lifecycle supports deletion of unissued drafts, voiding of issued
unallocated invoices, and reversal/refund followed by voiding for paid
documents. A settings-only Finance cleanup flow may soft-delete eligible
financial document bundles after the acting admin re-enters their password.

Soft deletion records the actor, timestamp, and reason and removes the target
from normal Finance projections. It never physically removes database rows.

## Rationale

Receipts document completed payment, while invoices represent a receivable.
Separating their display and lifecycle semantics prevents misleading debt
signals without creating a parallel accounting ledger.

Password re-authentication and a settings-scoped workflow make exceptional
purging deliberate. Soft deletion preserves recoverability and operational
traceability while keeping accidental records out of active finance views.

## Alternatives Considered

Leaving reversed receipts as overdue was rejected because it conflates a
corrected payment fact with a member debt.

Hard deletion was rejected because it destroys evidence and impedes recovery.

A sandbox environment was rejected for this scope at the product owner's
direction.

## Consequences

Finance query and aggregate paths must consistently exclude soft-deleted facts.
Receipt corrections must not block entitlement as overdue. The cleanup UI needs
search, explicit confirmation, and password re-authentication; its endpoint
must enforce those checks server-side.

## Implementation Notes

Pending implementation.
