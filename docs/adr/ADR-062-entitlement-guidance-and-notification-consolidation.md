# ADR-062: Entitlement Guidance and Notification Consolidation
Date: 2026-07-18
Status: Accepted

## Context
Admin workout assignment can be rejected by Finance for several distinct
entitlement reasons. The API already returns stable semantic codes, but the web
presentation currently collapses every unrecognized `403` response to a generic
permission message. That hides the corrective action from the coach, especially
when an athlete has no package, an inactive package, a package without personal
programming, or no remaining coaching allowance.

Assigned-workout creation also refreshes the athlete's plan without creating a
semantic notification. Booking approval does create notifications, but resolving
several requests in quick succession can create one alert per booking. The same
fan-out would be noisy when a coach assigns several workouts to one athlete.

## Decision
Keep Finance denial codes as the API contract and map each code to specific,
actionable, localized guidance in the web presentation layer. Member/athlete
surfaces explain what the current user's package lacks and direct them to
billing or their coach. Admin assignment surfaces explain what must be corrected
on the selected athlete's profile or package. Where available, canonical
channel, capability, allowance, and limit details travel as API parameters and
are humanized only at presentation time.

Add a `workout_assigned` notification type and emit it only after assignment
persistence and coaching-touchpoint finalization succeed. Consolidate rapid
`workout_assigned` and `booking_approved` deliveries per recipient and semantic
type into one notification using a short deterministic time bucket as the
deduplication key. Consolidated copy deliberately describes one or more affected
items, so the first persisted in-app notification and Web Push remain truthful
when later events in the same bucket are suppressed.

## Rationale
Stable backend codes preserve transport semantics and let every client choose
appropriate presentation without relying on English compatibility prose.
Actionable copy tells the coach whether to assign a package, renew it, change its
benefits, grant an allowance extension, or correct the athlete selection.

Time-bucket deduplication reuses the existing database uniqueness boundary and
Oban delivery pipeline. It prevents notification and push storms without adding
polling, mutable counters, cross-context schema access, or a second batching
store. Per-recipient keys ensure one athlete's activity never suppresses another
athlete's notification.

## Alternatives Considered
A generic friendlier `403` message was rejected because it still conceals the
different corrective actions.

Persisting every notification and grouping only in the frontend was rejected
because Web Push would remain noisy and unread counts would still be inflated.

A mutable notification-batch table with delayed aggregation jobs was rejected as
unnecessary complexity for short bursts. Exact counts can be added later if the
product needs long batching windows or digest schedules.

## Consequences
Notification types remain manually synchronized across the database constraint,
Ecto enum, push builder, inbox presentation, and tests, as already tracked by
TD-023.

Events outside the short consolidation window intentionally create a new alert.
Consolidated notifications use summary copy rather than an exact item count.

## Implementation Notes
Implemented stable, audience-aware presentation for every Finance entitlement
denial currently emitted by booking, execution, messaging, and programming
delivery. Member and athlete surfaces now retain `403` entitlement responses
instead of signing out or replacing them with a generic execution error. Admin
assignment surfaces use athlete-specific corrective copy. Channel, capability,
allowance, committed usage, and limit parameters remain canonical API data and
are humanized only by the localized web presentation layer.

Added `workout_assigned` across the notification database constraint, Ecto enum,
event dispatcher, message builder, inbox title presentation, Gettext catalogs,
and all twelve web locale catalogs. Successful assignment dispatch happens only
after Finance reservation finalization. `workout_assigned` and
`booking_approved` use per-user, per-type, one-minute deduplication buckets with
summary copy; database uniqueness suppresses both duplicate inbox rows and
duplicate Web Push enqueueing.

The local development migration completed successfully. Focused verification
covered 28 backend tests, the full backend suite completed with 440 tests and no
failures, and the full frontend gate completed lint, type checking, 45 tests,
OpenAPI contract regeneration/diff, and a production build. The architecture
boundary gate and Gettext freshness check also passed.

A rollback/cleanup-contained adapter check created two assignment events and two
approval events for one temporary user and observed exactly one
`workout_assigned` plus one `booking_approved` notification. The temporary user
and cascading notification rows were deleted immediately. Host-mode development
startup could not serve as the live harness because the existing host Argon2
native module is unavailable and MinIO was not running; this did not affect the
Compose migration, PostgreSQL-backed tests, frontend production build, or the
verified test-runtime adapter check. No implementation work was deferred and no
new technical-debt entry was added.
