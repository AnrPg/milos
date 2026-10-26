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

## §2 Pause, cancel and delete (2026-10-26)
Staff can pause, resume, cancel, restore and delete a class
(`POST /admin/schedule/slots/:id/state`, `manage_schedule`). Each takes the
same scope as an edit. The rules live in `Scheduling.Domain.ClassState` and the
use case is `ChangeClassState`; the scope is resolved by
`Application.SeriesScope`, which edits share.

- **Pause** (`paused_at`): no new bookings, waitlist joins or guests, and the
  waitlist is not promoted. Existing bookings stay. **Resume** clears it and
  promotes the waitlist.
- **Cancel** (`cancelled_at`, optional `cancel_reason` up to 280 characters,
  which members see): the class stays listed and is shown struck through.
  Every pending, approved or waitlisted booking is withdrawn in the same
  transaction, with a durable reconciliation job and no late-cancel charge.
  `:booking_cancelled` (by `:staff`) and `:class_cancelled` are published, so
  trials end as they do when a class is deleted. Each member gets one
  `class_cancelled` notification (bookings category). **Restore** works while
  the class is upcoming; released bookings don't come back.
- **Delete**: only a class without any booking. When several classes are
  reached, booked ones are skipped and counted (`skipped_with_bookings`). When
  only one class is reached, the action is refused with `class_has_bookings`.
- A cancel or delete of every upcoming class (`all`, every 1) sets the series
  to `ended`, so it creates no more classes. A pause never ends it.
- Classes that already started are skipped. A skip is an error only when the
  action reached a single class.

## §3 Every nth class
`every` (1–52) narrows any scope, for edits and state changes alike, to every
nth class counted from the acted-on class in date order, both forwards and
backwards (`SeriesEdit.every_nth/3`). Only `all` with `every` 1 updates the
series template or ends the series.
