# ADR-007: Scheduling Booking Approval and Timeout Flow
Date: 2026-06-08
Status: Accepted

## Context
Phase 3 introduces scheduled class slots, a member booking flow, admin
approval/rejection, and timeout escalation when bookings remain unresolved.
The design doc requires Application Services for cross-context operations and
forbids polling for real-time or delayed side effects.

The scheduling flow touches the Scheduling context, Oban background jobs, and
notification side effects. It also needs to preserve a responsive schedule UI
without embedding timeout logic into controllers or relying on periodic scans.

## Decision
Implement booking submission and resolution through dedicated Application
Services, use one Oban job per pending booking to trigger unresolved booking
timeout alerts, and make all Phase 3 booking side effects durable through Oban
jobs while keeping PubSub broadcasts for cross-context event fan-out.

## Rationale
Per-booking Oban jobs match the product requirement that timeout alerts fire at
`inserted_at + booking_timeout_minutes` without introducing cron polling or
controller-side timers.

Application Services keep cross-context orchestration explicit: scheduling owns
slot and booking persistence, while secondary effects such as notifications and
job cancellation run after the primary booking transition succeeds.

Timeout-job creation is part of the booking write boundary rather than a
best-effort follow-up step. That guarantees a `pending` booking cannot be
persisted without the matching timeout job reference that Phase 3 depends on.

This design also keeps the domain policy pure. Capacity, duplicate-booking, and
past-slot rules stay in a pure `BookingPolicy` module, while persistence and
job scheduling remain infrastructural concerns.

The schedule API accepts explicit UTC window boundaries (`start_at`, `end_at`)
from the web client. The client computes those from the user’s local calendar
view so the backend queries the exact visible window without guessing the
user’s timezone from a bare `start_date`.

## Alternatives Considered
Cron-style polling for stale bookings was rejected because it violates the
design doc's “no polling” rule, adds latency between timeout and alert, and
creates unnecessary repeated scans.

Putting timeout scheduling and cancellation directly in controllers was
rejected because it would bypass the required application layer and mix
transport concerns with orchestration.

Auto-approval implemented purely as a write command was rejected because the
flow still requires cross-cutting follow-up work such as notification emission
and timeout management.

## Consequences
Scheduling needs explicit persistence support for slots, bookings, and timeout
job lookup/cancellation boundaries.

Notifications begin in Phase 3 as minimal persisted booking alerts so the
approval workflow has a durable in-app signal before full Web Push delivery is
implemented in Phase 6.

Schedule reads that combine slot data with workout summaries or member/admin
identity details must be assembled above the bounded contexts rather than by
cross-importing foreign schemas.

## Implementation Notes
Phase 3 ships a new Scheduling context with `scheduled_classes` and `bookings`
tables, a pure `BookingPolicy`, minimal persisted `notifications`, and the
`BookingTimeoutJob` worker. Pending bookings store the inserted Oban job id on
`bookings.timeout_job_id`, which lets the resolution application service cancel
the exact timeout job without querying Oban tables from the application layer.
Timeout-job insertion now happens inside the booking write transaction, so a
`pending` booking cannot be committed without its matching timeout job
reference.

Schedule reads are assembled through `MilosTraining.Application.GetScheduleCalendar`
so the controller does not orchestrate cross-context data directly. That
service enriches scheduling records with published workout previews from the
Workouts context and member nicknames from Identity.

Cross-context booking side effects continue to emit `Phoenix.PubSub` events on
`booking:submitted`, `booking:resolved`, and `booking:timeout`. The
Notifications context now owns a dedicated subscriber that reacts to those
events by enqueueing durable Oban-backed notification writes. Notifications are
also written immediately through an idempotent create-once path so the UI
reflects approval and timeout state without waiting for a queue drain, while
the queued job remains as the retry mechanism if the synchronous write fails.
If both delivery paths fail, the system now emits an explicit error log instead
of silently dropping the notification side effect.

Phase 3 now also exposes authenticated Phoenix Channel delivery for user-facing
schedule updates. Internal PubSub events are bridged to a `schedule:lobby`
topic through a dedicated realtime relay so the schedule UI reacts to booking
and slot changes without controller polling or manual refresh loops. The
channel payloads intentionally stay lightweight (`schedule:refresh` plus ids /
reason metadata), and the web client reuses the existing REST endpoint as the
read-model source of truth.

Approval is capacity-safe at resolution time. Booking approval now locks the
booking row and its scheduled class row before counting existing approved
bookings, which prevents concurrent approvals from oversubscribing a slot.

The original `(scheduled_class_id, user_id)` unique index was narrowed to
active bookings only (`pending` and `approved`). That allows a member to submit
a fresh booking after a rejection while still preventing duplicate active
reservations for the same slot.

Scheduled class `training_type` remains a first-class field on the slot rather
than being forcibly overwritten from the linked workout. The create/update flow
still validates that the workout exists, but admins can now explicitly set the
slot type in the schedule editor to match the Phase 3 UI contract.

The web schedule uses a custom responsive multi-day column calendar rather than
`react-big-calendar`. The UI groups slots by the user’s local calendar day and
formats times locally, which avoids the UTC/local day drift that would
otherwise misplace late-night classes. The client now sends explicit UTC
`start_at` and `end_at` boundaries derived from the visible local calendar
window so the backend queries the exact intended range without inferring
timezone semantics from a bare date. For month view, the query window is now
the actual calendar month while the client renders leading/trailing empty grid
cells locally, keeping the API payload semantically aligned with the selected
view. The schedule UI also ships the dedicated `/admin/schedule` route,
defaults to a 3-day window on mobile, and renders workout preview sections as
collapsible panels in the slot popup to match the approved Phase 3 UX.

Admin schedule reads now batch member identity lookups instead of resolving
each booking nickname one record at a time, and member-facing schedule payloads
only expose active (`pending` or `approved`) bookings as the current booking so
rejected history does not block rebooking in the UI.

Deleting slots with existing bookings is intentionally blocked for now. The
design doc calls for an admin confirmation flow, but the current backend
chooses safety over destructive deletion until a clearer cancellation/archive
path is added.
