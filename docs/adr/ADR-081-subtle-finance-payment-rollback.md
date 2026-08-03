# ADR-081: Subtle Finance Payment Rollback
Date: 2026-08-03
Status: Accepted

## Context
Admins can already record append-only payment reversals through the Finance API,
and Finance projections restate revenue net of those reversal facts. The
compact admin finance member panel, including receipt mode, does not expose
that correction path where the payment or receipt was created.

## Decision
Expose payment rollback as a subtle icon action on eligible payment and receipt
rows in the compact member finance panel.

## Rationale
The rollback action should be close to the financial fact it corrects while
remaining visually quieter than the primary +money actions. Reusing the
existing Finance reversal endpoint preserves append-only accounting, invoice
balance recalculation, and net revenue projection semantics.

## Alternatives Considered
A separate reversal form was rejected for the compact panel because it already
exists in the legacy full profile and makes the correction path less
discoverable from receipt mode.

Voiding the receipt invoice was rejected because paid receipt invoices still
need an audited payment reversal, not a destructive invoice lifecycle shortcut.

## Consequences
The frontend must compute remaining reversible payment amount from payment facts
and reversal facts, hide the icon for fully reversed or non-reversible rows, and
invalidate all Finance/dashboard/statistics query surfaces after rollback.

## Implementation Notes
Implemented in the compact admin finance member panel. Receipt rows resolve the
backing payment through `finance_invoice_id`; payment rows use the payment fact
directly. The rollback icon is hidden for non-paid/non-waived payments and for
payments whose remaining reversible amount is zero.

The action posts the remaining reversible amount to the existing Finance
payment-reversal endpoint with an idempotency request id, then invalidates the
admin Finance, dashboard, analytics, and user finance dossier query surfaces so
net revenue/statistics restate like the +money path. No schema, OpenAPI, or
backend accounting changes were required because ADR-019 and ADR-021 already
own reversal facts and net projections.
