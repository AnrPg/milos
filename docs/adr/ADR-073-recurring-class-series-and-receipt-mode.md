# ADR-073: Recurring class series and receipt mode
Date: 2026-07-31
Status: Accepted

## Context
Admins need to define a class once and have concrete bookable occurrences repeat
on selected weekdays, with a custom public name, duration, optional end date, and
excluded dates. More than one class may start at the same time. External calendar
feeds must retain recurrence semantics rather than presenting an unrelated list
of one-off events.

Small gyms also need a simpler cash workflow. They receive money and immediately
give the member a receipt; they do not need to think in terms of drafting,
issuing, allocating, or later settling an invoice. Finance already has audited
invoice and payment facts, and replacing those facts would create a second
accounting model.

## Decision
Scheduling owns a `class_series` aggregate containing the recurrence rule and
the class defaults. Every bookable occurrence remains a `scheduled_class` row
linked to its series and snapshots the public class name and duration. Creating a
series validates and expands its rule transactionally into concrete occurrences.
The rule supports weekly recurrence, one or more ISO weekdays, an IANA timezone,
an optional inclusive end date, and excluded local dates. Open-ended series are
materialized through a rolling horizon and extended by an idempotent Oban job.

No uniqueness rule is introduced for a start time. Only
`(class_series_id, scheduled_at)` is unique, so distinct series and one-off
classes may overlap.

Admin calendar feeds serialize a series as one iCalendar event with `RRULE`,
`EXDATE`, and the configured duration. Individually booked member occurrences
remain individual events because booking one occurrence does not imply booking
the whole series.

Finance gains a configurable `document_mode` of `invoice` or `receipt`.
Receipt mode is a presentation and workflow policy, not a second accounting
ledger. One Finance command transaction creates a manual invoice for the
received amount, issues it immediately, records an equally valued paid payment
against it, and returns a receipt projection. The invoice number remains the
durable receipt reference. Existing invoice mode and all reversal/refund rules
remain available.

## Rationale
Concrete scheduled-class rows preserve the existing booking, attendance,
capacity, entitlement, notification, and realtime contracts. A separate series
aggregate preserves the user's recurrence intent and supports correct calendar
export without treating generated occurrences as unrelated manual slots.

Snapshotting name and duration on each occurrence makes historical calendar and
receipt-like attendance records stable if the series is edited later.

Keeping receipts on invoice/payment facts reuses the existing append-only
accounting and reversal rules. The one-step command removes accounting vocabulary
from the small-gym workflow without weakening auditability or creating a second
balance calculation.

## Alternatives Considered
Generating occurrence dates only in the browser was rejected because the rule
would not be durable, other clients could diverge, and calendar export could not
reconstruct recurrence reliably.

Expanding recurrence during schedule reads was rejected because reads must not
mutate state and booking requires stable concrete slot identifiers.

Preventing overlapping start times was rejected because parallel classes are an
explicit product requirement.

Creating a standalone receipt table was rejected because it would duplicate
invoice references, payment allocation, refund, and revenue semantics.

Renaming invoices to receipts everywhere was rejected because larger gyms still
need the full receivable lifecycle.

## Consequences
Series creation is bounded to protect request and transaction size. Open-ended
series require an idempotent extension job and a materialization watermark.
Editing a single generated occurrence does not silently rewrite the recurrence
rule; series-wide editing is a separate explicit command.

Receipt mode can only issue a receipt for money actually recorded in the same
transaction. Refunds continue to use append-only payment reversals and do not
erase the original receipt.

## Implementation Notes
Recurring series are implemented with a pure recurrence-rule module, concrete
scheduled-class materialization, a rolling-horizon extension worker, and recurring
iCalendar serialization for admin feeds. Occurrence creation continues through the
Scheduling store transaction, while the cross-context Application Service verifies
the workout and class type through public APIs before publishing the schedule event.

IANA timezone and DST conversion uses `Tz.TimeZoneDatabase`. `tzdata` was evaluated
but cannot resolve beside the project's Hackney 4.x requirement; `tz` implements
Elixir's standard `Calendar.TimeZoneDatabase` behavior without that dependency
conflict. Tests verify `Europe/Athens` wall time conversion to UTC, selected ISO
weekdays, excluded dates, open-ended horizons, and recurring iCalendar output.

The admin UI uses a compact “Create series” modal: core recurrence fields remain
visible, while capacity, booking timeout, and auto-approval stay in an optional
disclosure and inherit the persisted Scheduling defaults.

Finance receipt mode is implemented as one outer Ecto transaction that creates a
manual-charge invoice, issues it, and records the equal payment before returning a
receipt projection. The API exposes that workflow as a dedicated member receipt
endpoint, while `document_mode` lets the admin UI replace invoice lifecycle copy and
controls with a receive-money form. The resulting paid document uses the existing
private client-side document export path, so no parallel receipt ledger or public
document URL was introduced.

An iCalendar edge case discovered during verification changed recurring `DTSTART`
to the first materialized occurrence in the feed rather than the series boundary.
This keeps `DTSTART` aligned with `BYDAY` when `starts_on` is not itself a selected
weekday. Member feeds continue to contain only individually booked occurrences.

Verification completed on 2026-08-01 with the full backend precommit gate (497
tests), frontend unit tests (96 tests), type-check, lint, localization validation,
OpenAPI regeneration, and a production Next.js build. A Docker live test created
two distinct recurring series at the same `Europe/Athens` wall time, confirmed two
weekly RRULE events with the configured end/exclusion semantics, and recorded a
EUR 25.00 cash receipt whose backing invoice was immediately `paid` and marked
`document_kind: receipt`. No additional deferred work was introduced by this
implementation.
