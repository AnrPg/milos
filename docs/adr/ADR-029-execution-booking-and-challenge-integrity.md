# ADR-029: Execution, Booking, and Challenge Integrity
Date: 2026-06-13
Status: Accepted

## Context
Several user-facing writes currently acknowledge state before proving the
relationship or durable follow-up work that gives the state business meaning:

- workout execution accepts a caller-supplied source label without proving an
  assignment or approved class booking
- workout completion relies on volatile PubSub for durable gamification updates
- workout deletion removes execution history despite the nullable workout
  reference being designed to preserve it
- auto-approved booking is implemented as pending creation followed by a
  separate approval transition
- seasonal challenge concurrency is checked before insert without a
  transaction-level concurrency boundary

These gaps can create unauthorized execution facts, missing gamification
projections, ghost pending bookings, destroyed audit history, and more than
three overlapping active challenges.

## Decision
Apply the following integrity rules:

1. Execution starts must bind to an authorized source relationship. Assigned
   starts require an assignment that belongs to the athlete and references the
   requested workout. Class starts require an approved booking that belongs to
   the member and whose class references the requested workout. Self-selected
   starts are limited to members and admins.
2. Workout completion enqueues a unique Oban completion-processing job before
   the API acknowledges durable post-completion processing. PubSub completion
   broadcasts remain realtime UI signals only.
3. Workout deletion preserves execution records. The existing foreign key
   nilifies `master_workout_id` when the workout definition is deleted.
4. Auto-approved booking locks the class capacity boundary and inserts an
   approved booking directly, without creating a pending row or timeout job.
5. Seasonal challenge limit validation and insertion occur in one serializable
   transaction with retry on serialization conflicts.

## Rationale
Source relationships belong at the application/use-case boundary because they
span Identity, Scheduling, Workouts, Finance, and Execution.

Oban provides a durable PostgreSQL-backed handoff and retry lifecycle for
gamification projections. PubSub remains appropriate for transient browser
refresh events.

Execution records are audit history and feed coaching and gamification facts.
Deleting a workout definition must not erase completed user activity.

Direct approved insertion removes the intermediate state that causes ghost
pending bookings. Serializable challenge creation prevents concurrent
administrative requests from both passing the same pre-insert count.

## Alternatives Considered
Treating execution source as a trusted enum was rejected because it does not
prove user-workout authorization.

Keeping PubSub plus stronger error logging was rejected because logging cannot
recover a lost completion event.

Recomputing gamification after destructive execution deletion was rejected
because deletion of historical workout activity is contrary to the audit-trail
model.

Cleaning up failed auto-approval after the fact was rejected because direct
approved creation avoids the invalid intermediate state entirely.

An application-level challenge count check was rejected because it remains
race-prone under concurrent requests.

## Consequences
Execution start and timer-sequence contracts require source relationship
metadata for assigned and class-booking flows.

Completion processing becomes eventually consistent but durable, with Oban
retrying failures. Tests that intentionally disable Oban use synchronous
processing to preserve deterministic behavior.

ADR-011's decision to hard-delete workout executions is superseded by this ADR.
Scheduling slots and assignments remain deleted with the workout, while
execution history remains.

## Implementation Notes
Execution records now persist `source_reference_id`. Start and timer-sequence
use cases validate assignments and approved bookings through their owning
contexts before reading or writing execution data. The API contract requires a
source, and assigned/class-booking flows require the matching relationship ID.

Execution completion and the unique Oban completion job are committed in one
database transaction. The former PubSub gamification handler was removed;
`workout:completed` remains available for realtime UI refresh only. Test
environments that disable Oban process completion projections synchronously.

Workout deletion no longer calls or exposes an execution-history deletion
command. PostgreSQL nilifies the deleted workout reference while retaining the
execution fact.

Auto-approved bookings lock the class row, recheck approved capacity, and
insert directly as approved. No timeout job or pending state is created.

Seasonal challenge creation validates and inserts within a serializable
transaction and retries serialization conflicts. Existing schedule-policy
tests continue to cover the maximum-three overlap rule.
