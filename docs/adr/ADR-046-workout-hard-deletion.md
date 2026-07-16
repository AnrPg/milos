# ADR-046: Workout Hard Deletion Across Dependent Contexts (Historical Renumbering)
Date: 2026-06-09
Status: Superseded in part by ADR-029

> Renumbered from the duplicate ADR-011 identifier on 2026-07-15. The original
> decision date and content are retained; only its unique catalogue identity changed.

## Context
The product design for `/admin/workouts` explicitly includes deleting existing
workouts, but the current implementation only supports create, draft autosave,
publish, and assignment. The persistence model also spans multiple bounded
contexts:

- `Workouts` owns the master workout plus assigned-workout headers
- `Scheduling` stores class slots that reference `master_workouts`
- `Execution` stores workout execution history that references `master_workouts`

The existing foreign keys are intentionally mixed: assigned workouts cascade on
delete, scheduled classes restrict deletion, and workout executions nilify the
reference. That means “delete workout” is not currently a coherent operation.

## Decision
Implement workout deletion as an explicit admin-only hard-delete application
service that removes dependent scheduling slots, bookings, booking timeout job
links, and execution records before deleting the master workout.

## Rationale
An application service is required because the operation crosses bounded
contexts and must not be orchestrated in controllers.

Hard deletion matches the user request and avoids retaining orphaned or
semantically broken records such as execution rows with `master_workout_id =
NULL` or schedule slots that point at a workout the admin intentionally removed.

Deleting dependent schedule slots and bookings keeps the schedule surface
consistent with the workout library and avoids foreign-key conflicts. Removing
execution rows at the same time keeps workout history aligned with the hard
deletion semantics instead of preserving detached execution artifacts.

## Alternatives Considered
Keeping the current `nilify_all` execution behavior was rejected because it
preserves records the UI cannot fully recover or interpret without the workout
definition.

Soft deletion or archival was rejected because the request is explicitly for
hard deletion and the current product/docs do not define archive semantics for
workouts.

Relying only on database foreign-key cascades was rejected because the current
schema does not encode one consistent deletion policy across scheduling and
execution, and it would not cancel attached booking timeout jobs.

## Consequences
Deleting a workout is permanently destructive for:

- the workout definition
- assigned workout records tied to that workout
- schedule slots and bookings tied to that workout
- execution history tied to that workout

The delete flow must remain admin-gated and should require clear user
confirmation in the admin UI.

Scheduling and execution contexts need dedicated delete-by-workout commands so
the application service can orchestrate the operation without bypassing bounded
context APIs.

## Implementation Notes
Phase 2/3/4 code now exposes `DELETE /api/admin/workouts/:id` through an
admin-only controller action that delegates to
`MilosTraining.Application.DeleteWorkout`.

The original implementation service:

1. reads impacted athlete-assignment recipients from the Workouts context
2. reads impacted booked-member recipients from the Scheduling context
3. hard-deletes schedule slots for the workout (including their bookings and
   booking timeout jobs) through the Scheduling context
4. hard-deleted workout executions through the Execution context
5. hard-deletes the master workout through the Workouts context
6. emits schedule refresh broadcasts for removed slots
7. sends post-delete `workout_changed` notifications to affected athletes and
   booked members

Assigned-workout rows continue to cascade from the workout foreign key, so the
Workouts context does not need a second explicit delete pass for them.

ADR-029 supersedes the execution-deletion portion of this decision. Workout
executions are now preserved and their `master_workout_id` is nilified by the
existing foreign key when the workout definition is deleted.

User notifications are sent after the destructive delete completes. Notification
delivery failures are logged but do not roll back the primary deletion flow,
which preserves the project rule that non-critical side effects must not abort
the main operation.
