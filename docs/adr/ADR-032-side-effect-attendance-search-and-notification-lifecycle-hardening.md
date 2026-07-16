# ADR-032: Side Effect, Attendance, Search, and Notification Lifecycle Hardening
Date: 2026-06-13
Status: Accepted

## Context
The Phase 8 hardening review found several cross-layer defects where secondary
effects or read-model shortcuts could corrupt user-visible state:

- Booking submission could commit a booking and then return an error when
  notification dispatch failed.
- Admin attendance writes accepted arbitrary user/class pairs without proving
  approved class participation.
- Admin search index replacement upserted current documents but did not remove
  stale documents for users that no longer belonged in the indexed set.
- Workout reschedule notifications used a semantic type that the persisted
  notification schema and database constraint did not accept.
- Browser push delivery marked notifications read during delivery instead of
  during user click-through.
- Admin analytics exposed raw debug facts rather than a production dashboard
  composed from owning context summaries.

These issues cross bounded contexts, so they require explicit application
orchestration and context-owned ports rather than controller or UI-only fixes.

## Decision
Primary commands must return the committed primary result after successful
persistence. Non-critical notification dispatch failures are logged and routed
through the Notifications retry/fallback path, but they do not change the result
of booking submission.

Attendance recording uses a Scheduling-owned participation policy: admin
attendance can only be recorded for a user with an approved booking for the
target scheduled class. The application service asks Scheduling for approved
booking participation before calling the Scheduling attendance write command.

Admin search `replace_documents/1` means true replacement of the admin-member
index. The Meilisearch adapter removes stale indexed documents before adding
the current projection set. PostgreSQL remains the authoritative fallback.

Notification semantic types must be accepted by the Ecto enum and database
constraint before dispatchers can emit them. `workout_moved` is a supported
notification type.

Push delivery and user consumption remain separate lifecycle events. The
service worker shows the push notification without marking it read; on
notification click it calls the authenticated click endpoint, which records the
click and marks the notification read.

Admin analytics renders production-facing KPI cards, grouped summaries, and
bounded lists from existing owning-context summaries instead of raw JSON blobs
or phase/debug labels.

## Rationale
Notifications, push delivery, and analytics are secondary effects. Returning
errors for already-committed primary writes produces duplicate retries and
untruthful UI states.

Scheduling owns bookings and attendance, so the class-participation policy
belongs behind the Scheduling public API. Analytics can still project
attendance facts, but it should not become the permission boundary for class
participation.

Search documents are denormalized read models. True replacement semantics keep
the index aligned with the current source projection while preserving
PostgreSQL as the source of truth when Meilisearch is unavailable.

Read, delivered, and clicked have distinct product meanings. Recording reads
on push delivery makes unread counts and click analytics inaccurate.

## Alternatives Considered
Keeping notification dispatch inside booking's `with` chain was rejected
because it exposes committed bookings as failed operations.

Validating attendance in the controller was rejected because controllers must
not contain business policy and cannot reliably protect all future call sites.

Deleting stale search documents one-by-one based on source deltas was rejected
for the MVP because query-time rebuild is still the accepted temporary
projection path. Clearing and re-adding the bounded admin-member index is
simpler and matches the existing replacement contract.

Marking push notifications read from the service worker during delivery was
rejected because delivery is not evidence of user consumption.

## Consequences
Booking notification failures will be observable in logs/notification jobs, but
clients receive the persisted booking and can avoid duplicate retries.

Attendance writes now require an approved booking. Manual walk-in attendance
would need a future explicit admin override workflow rather than bypassing the
participation policy.

Admin search indexing remains query-time for now and can still be moved to
event/job-driven incremental updates under TD-014. The adapter's replacement
operation may briefly empty the bounded index during rebuild; PostgreSQL
fallback remains available for operational correctness.

Notification type additions still require keeping the schema enum, database
constraint, dispatcher, push builder, and frontend renderer aligned until a
single generated notification-type contract replaces the duplication.

## Implementation Notes
Implemented on 2026-06-13.

`SubmitBooking` now treats notification dispatch as non-critical after the
booking write succeeds. Dispatch errors are logged and the persisted booking is
returned to the caller.

`AdminRecordAttendance` now asks Scheduling for an approved booking for the
target user and class before writing attendance. The approved booking id is
stored on the Scheduling-owned attendance fact. Pending bookings and missing
bookings return `:attendance_requires_approved_booking`.

The Meilisearch admin-member adapter now deletes all documents in the bounded
admin-member index before posting the current projection set, making
`replace_documents/1` a true replacement operation while TD-014 covers the
future event/job-driven incremental indexer.

`workout_moved` was added to the notification schema enum, database check
constraint, push-message builder, and focused notification tests.

The push service worker no longer marks notifications read during push
delivery. It records a click through `/api/notifications/:id/click` only when
the user clicks the browser notification, using the cached access token when
available.

The admin analytics page now renders KPI cards, bounded breakdown lists, and
operational status fields instead of raw JSON/debug blocks.

## Durable Effects and Health Amendment — 2026-07-15

All important post-commit effects use a transactional outbox and idempotent Oban
dispatcher. Domain/context commands record facts and effect intents atomically;
notification, analytics, cache invalidation, search indexing, entitlement
release, and realtime publication retry independently with observable terminal
failure state. Readiness reports PostgreSQL, Redis, Oban, Meilisearch, and MinIO
separately; liveness reports only process health and cannot claim dependency
health while degraded.
