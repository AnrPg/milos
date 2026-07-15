# ADR-034: Finance invoice reference format
Date: 2026-06-16
Status: Accepted

## Context
Finance invoices already exist as durable receivables, but the current
`invoice_number` format is a short UUID fragment. That identifier is unique but
not operator-friendly in member billing history, admin payment history, or
manual finance workflows where humans need to identify the linked invoice at a
glance.

The app needs invoice references that remain unique under concurrent creation,
carry basic billing context, and can be shown consistently across member and
admin surfaces without adding a second public identifier field.

## Decision
Keep `finance_invoices.invoice_number` as the public invoice identifier and
reformat it as a sequence-backed human-readable reference:

`INV-<sequence>-<package-segment>-<utc-timestamp>`

Existing invoice records will be backfilled into the new format, and new
invoice numbers will be generated from a PostgreSQL sequence plus a sanitized
package/manual segment and UTC creation timestamp.

## Rationale
Reusing the existing `invoice_number` field avoids contract churn while
improving readability everywhere that already consumes invoice references.

A database sequence provides monotonic uniqueness without race-prone
application-side counting. Including the package/manual segment gives operators
light contextual meaning, and the UTC timestamp helps distinguish invoices in
support or accounting conversations.

## Alternatives Considered
Keeping the UUID-fragment format:
rejected because it is hard to scan and does not help operators link payments
to invoices quickly.

Adding a second public invoice identifier column:
rejected because it duplicates meaning already owned by `invoice_number` and
would require broader contract changes.

Using only timestamps without a sequence:
rejected because concurrent invoice creation can collide and does not guarantee
stable monotonic ordering.

## Consequences
Invoice references become longer and more descriptive. Existing invoices will
change displayed reference values after the backfill migration.

Future invoice exports, PDFs, notifications, and support tools should treat
`invoice_number` as the canonical human-facing invoice reference.

## Implementation Notes
Implemented with a dedicated Finance domain formatter, a PostgreSQL-backed
sequence for new invoice creation, and a migration that rewrites existing
invoice numbers using invoice insertion order plus package/manual context.

Member billing now hides the credits panel when there is no positive available
credit or referral credit to show, and the invoice history table is explicitly
scrollable on both axes for dense histories. Admin payment history now renders
the linked invoice reference instead of the generic `invoice-linked` label.
