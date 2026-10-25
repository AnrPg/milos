# ADR-200: Edits to a class of a series reach this class, all upcoming classes, or a date range; classes can be duplicated
Date: 2026-10-25
Status: Accepted

## Context
A class series (ADR-097) creates one class per date ahead of time (`class_series`
→ `scheduled_classes`, materialised up to a horizon and extended later). Staff
could only edit one class at a time, so changing a series (a new coach, a new
time, more places) meant editing every class. Staff also had no way to copy a
class to another day. ANR asked for "apply only to this instance / to all
instances / for a specific date range" and a duplicate action (2026-10-25).

## Decision
- `PATCH /admin/schedule/slots/:id` takes `series_scope`: `this` (default),
  `all`, or `range` with `range_from` and `range_to` (gym-local dates, both
  included). The response adds `updated_count`.
- The edited class always takes the whole edit, including its own date and WOD.
- The other classes reached take the shared fields only: name, class type,
  duration, capacity, auto-approve, booking timeout, branch and coach. When the
  start time of day changed, each one moves to the new time on its own date, on
  the series's clock (DST-safe via `RecurrenceRule.at_local_time/3`). Their
  dates and WODs stay their own, because each class has its own WOD (ADR-176).
- Only upcoming classes are touched. Classes that already started are history.
  A new time that would already be past today, or that falls in a DST gap,
  leaves that class's time as it was.
- `all` also updates the series itself, so classes it creates later carry the
  edit. `range` leaves the series alone. A range past the classes created so
  far creates them first, so every date in it is reached.
- All of it runs in one transaction: if one class cannot take the edit (for
  example fewer places than its approved bookings), nothing changes.
- The class popup has «Duplicate»: it opens a new class form with the class's
  settings, outside any series, at its branch. A class already past is copied
  to the same time on the next week ahead.

## Rationale
The scope rules live in a pure domain module (`Scheduling.Domain.SeriesEdit`),
with three store calls behind the port (`get_class_series`, `list_series_slots`,
`update_class_series`). The use case (`UpdateScheduledSlot.update_in_scope/3`)
reuses the single-class update path for every class, so capacity, booking and
WOD-filing rules stay in one place.

## Alternatives Considered
- "This and following" instead of "all": "all upcoming" already excludes the
  past, and a date range covers "from here until a date".
- Splitting the series at the range: more rows and harder rules, for the same
  result on the classes staff see.
- Copying the WOD to all classes: it would overwrite each day's own WOD.

## Consequences
- Editing the class's date moves only that class, whatever the scope.
- Weekdays, start/end dates and excluded dates of a series are still edited
  only by creating a new series.
