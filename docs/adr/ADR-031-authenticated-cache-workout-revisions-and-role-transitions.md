# ADR-031: Authenticated Cache, Workout Revisions, and Role Transitions
Date: 2026-06-13
Status: Accepted

## Context
Production review found three cross-cutting lifecycle flaws:

- the execution Service Worker cached authenticated API responses by URL, so a
  shared browser could return one user's workout or execution data to another
  user before the request reached server authorization
- reopening a published workout changed the canonical record to `draft`, which
  made every published-only consumer temporarily lose the referenced workout
- role changes updated only `users.role`, leaving active bookings, assignment
  links, timeout jobs, and role-scoped browser state inconsistent with the new
  role

The same review found that the last-admin check was split across a count and an
update, allowing concurrent demotions to remove every admin.

## Decision
Authenticated workout cache entries are partitioned by the current user id.
The page communicates the active user id to the Service Worker on session
establishment, and clears all authenticated workout caches before changing or
removing that identity. The Service Worker never serves an authenticated cache
entry when no user identity has been established.

Published workout content remains available while a new draft revision is
edited. Reopening reconstructs `draft_data` but leaves the canonical workout
status and materialized sections published. Autosave updates only `draft_data`;
republishing atomically replaces the materialized section tree.

Role changes run through `MilosTraining.Application.UpdateUserRole`. The
service asks the currently owned contexts to reconcile active role-specific
state before changing Identity:

- member to another role cancels active future bookings and their timeout jobs
- athlete to another role archives active assignment links while retaining
  assignment messages and historical records for admin audit
- the affected user's browser session receives a user-scoped invalidation
  signal after the transition

Identity performs the role update and last-admin invariant in one database
transaction while holding a PostgreSQL transaction advisory lock dedicated to
admin-role membership.

## Rationale
User partitioning and explicit invalidation keep offline resilience inside the
authorization boundary while preserving cache-first recovery for the same
user.

Keeping published rows live during editing avoids breaking scheduled classes,
assignments, executions, reviews, and timer generation. The existing
`draft_data` field already provides a separate mutable authoring payload, so no
destructive schema change is required.

Role-owned state belongs to Scheduling and Workouts, while Identity owns the
role scalar. An application service is therefore the correct orchestration
boundary. Archiving assignment links preserves coaching history without
continuing to expose active athlete programming after the user becomes a
member.

A transaction advisory lock serializes all admin promotion and demotion
updates across application nodes without importing unrelated context state into
Identity or relying on process-local locks.

## Alternatives Considered
Disabling offline caching entirely was rejected because execution recovery is a
documented product requirement.

Putting access tokens in cache keys was rejected because it would retain a new
cache namespace after every token rotation and expose credential material to
cache metadata.

Creating a new workout revisions table was considered. It provides fuller
revision history, but the current schema already separates published sections
from mutable `draft_data`; keeping the published status during edits fixes the
availability defect with less migration and API churn.

Deleting assignment messages on role change was rejected because those
messages are coaching audit history. Leaving active links untouched was
rejected because member-facing authorization would no longer match persisted
programming state.

Checking the admin count before a normal update was rejected because the check
and mutation are not atomic.

## Consequences
The frontend session provider and Service Worker share a small message
protocol for setting and clearing the active cache user.

Admin workout lists must distinguish a published workout with pending
`draft_data` from a newly created draft by status rather than assuming that all
editable records have `status: draft`.

Scheduling and Workouts gain explicit role-transition cleanup commands exposed
through their public APIs. Cleanup is limited to active future state;
historical bookings, executions, and messages remain available for audit.

Role updates may wait briefly behind another concurrent admin-role update, but
cannot commit a state with zero admins.

## Implementation Notes
Implemented without destructive schema changes:

- The Service Worker now uses `milos-workout-runtime-v2-user-{user_id}` cache
  namespaces, ignores authenticated workout requests until a session user is
  established, and clears legacy/all user caches whenever the active identity
  changes.
- `SessionProvider` sends cache-user updates on bootstrap, login, registration,
  sign-out, refresh failure, and role-change session invalidation.
- `/workouts` now uses the shared `AuthGuard` for member/admin access, and the
  execution recovery route waits behind the same guard instead of redirecting
  while session restoration is still loading.
- Workout-browser and admin-dashboard schedule requests now send exclusive
  local-window boundaries as ISO-8601 UTC datetimes. The schedule helper derives
  its parameter types from the generated OpenAPI schema.
- Identity serializes admin-role membership updates by locking the ordered admin
  set and target user in one transaction. Concurrent demotions are covered by a
  regression test and cannot leave zero admins.
- `UpdateUserRole` now coordinates Scheduling and Workouts before the Identity
  update. Future active bookings are deleted with timeout cancellation, while
  active assignment links are marked `archived`; messages and assignment
  history remain available to admins.
- Reopening a workout reconstructs `draft_data` while retaining
  `status: published`. Republish remains transactional and clears `draft_data`
  only after replacing the live section tree.
- Publish content validation now walks nested sections recursively, allowing
  container sections whose exercises live only in child sections.
- Meilisearch is pinned to `v1.45.2` plus digest, and MinIO is pinned to
  `RELEASE.2025-09-07T16-13-09Z` plus digest.

No follow-up debt was deferred from these findings. The broader handwritten
Phase 8 frontend client migration remains tracked separately as TD-021.
