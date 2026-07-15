# ADR-014: User-Scoped Realtime Sync for Landing and Assigned Workouts
Date: 2026-06-11
Status: Accepted

## Context
The existing realtime design already covers three transport topics:
`schedule:lobby`, `notifications:{user_id}`, and `execution:{execution_id}`.
That is enough for schedule mutations, notification inbox changes, and active
execution tabs, but it leaves other user-scoped read models stale until manual
refresh.

Two gaps became visible in production:

- athlete/admin assigned-workout calendars (`/my-workouts`) do not refresh when
  assignments are created, edited, deleted, rejected, or globally republished
- the landing page can continue showing pre-completion execution summaries or
  stale gamification snippets until a manual refresh or cache expiry

The landing page is also backed by Redis cache-aside with a 60-second TTL, so
correctness depends not only on invalidating the cache in the backend but also
on telling already-open browser sessions to re-fetch the authoritative REST
payload.

## Decision
Add a dedicated authenticated Phoenix Channel topic, `sync:{user_id}`, for
lightweight user-scoped invalidation events. Backend commands that change
landing-facing or assigned-workout-facing read models publish internal
`"user:sync"` PubSub events, which are bridged to the external socket topic as
`sync:refresh` messages carrying scopes and reason metadata.

The client treats this topic as an invalidation stream, not as a source of
truth:

- React Query-backed landing reads invalidate and refetch `["landing"]`
- non-query screens such as `/my-workouts` receive a browser event and rerun
  their existing REST load path

The existing schedule, notifications, and execution topics remain in place and
continue to own their dedicated read-model refresh behavior.

## Rationale
User-scoped invalidation solves the staleness problem without introducing new
read models, polling loops, or cross-context coupling in controllers.

Keeping the socket payload lightweight preserves the current architectural rule
that REST remains the authoritative read surface, while still giving open tabs a
timely signal that their cached data is stale.

Using scopes lets one topic cover multiple user-owned surfaces without forcing
every page to refresh on every event.

## Alternatives Considered
Reusing `notifications:{user_id}` for generic UI refresh was rejected because
notification persistence and generic view invalidation are different concerns.
Some user-scoped state changes do not create a notification record, and
overloading the inbox channel would make its semantics ambiguous.

Adding more bespoke Phoenix Channel topics for every screen was rejected because
it would fragment the contract and duplicate subscription logic across
user-owned pages that all just need lightweight re-fetch signals.

Relying on Redis TTL or `refetchOnWindowFocus` alone was rejected because it
does not update already-open views promptly and still leaves obvious
cross-session drift.

## Consequences
Backend application services must now identify the affected user ids when a
write changes assigned-workout or landing-facing read models.

The frontend gains one new global realtime bridge that maps socket invalidation
events to query invalidation and local browser events for non-query screens.

The new topic is additive. Existing schedule, notification, and execution
subscriptions do not change their semantics.

## Implementation Notes
- Added `MilosTraining.Application.BroadcastUserSync` as the internal
  application-level emitter for user-scoped invalidation events.
- Added `MilosTrainingWeb.SyncChannel` and registered `sync:*` on the socket.
  Join authorization is strict: only the authenticated user may subscribe to
  `sync:{their_id}`.
- Extended `InvalidateLandingPages` so cache invalidation and browser refresh
  signals stay coupled. Landing cache invalidation now emits `landing` sync
  events for one user, many users, or all users.
- Wired the following backend write paths into sync events:
  - assigned workout create/update/delete/reject
  - workout completion
  - admin -> athlete coaching note writes
  - challenge create/update/delete
  - admin settings updates
  - admin workout draft/workout/scale-level mutations
  - workout republish/substitution when scheduled slots or assignments are
    affected
- Added `RealtimeSyncBridge` on the frontend as the single authenticated
  subscription point for `sync:{user_id}`. It maps scopes to React Query
  invalidation and emits a local browser event for imperative screens.
- Added local browser listeners for:
  - assigned workouts console
  - admin workout list
  - workout creation canvas
- Extended `/workouts` to subscribe to the existing `schedule:lobby` topic so
  schedule-driven workout browse state updates live too.
- Added per-editor `editor_session_id` metadata to draft autosaves so the workout
  editor can sync across tabs without causing self-triggered autosave/refetch
  loops in the originating tab.
