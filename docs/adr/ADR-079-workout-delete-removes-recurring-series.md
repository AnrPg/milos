# ADR-079: Workout delete removes recurring class series
Date: 2026-08-02
Status: Accepted

## Context
ADR-046 defines admin workout deletion as a cross-context hard delete. ADR-073
later introduced recurring class series in Scheduling. A class series stores a
required `master_workout_id`, while concrete scheduled classes are generated from
that series. The original workout delete service deletes generated scheduled
classes but does not delete the owning series record, so PostgreSQL can reject
the final master workout deletion.

## Decision
Hard-deleting a workout also deletes all recurring class series that reference
that workout. The Scheduling context owns the series deletion command, and
`MilosTraining.Application.DeleteWorkout` orchestrates it after deleting concrete
scheduled classes and before deleting the master workout. The `class_series`
foreign key to `master_workouts` is changed to `ON DELETE DELETE ALL` as a
database-level backstop for the same product rule.

## Rationale
The admin confirmation already describes workout deletion as removing related
schedule data. Keeping a recurring series without its workout definition is not a
valid scheduling state, and requiring admins to discover and remove the series
manually makes hard deletion brittle.

Putting the operation behind a Scheduling command preserves bounded-context
ownership. The database cascade protects data integrity if a future code path
deletes a workout without using the application service.

## Alternatives Considered
Ending or cancelling the series instead of deleting it was rejected because the
requested operation is explicitly a hard delete and the workout definition would
no longer exist for future materialization.

Changing `class_series.master_workout_id` to nullable with `ON DELETE SET NULL`
was rejected because a recurring class series cannot generate valid future
occurrences without a workout.

Relying only on the database cascade was rejected because Scheduling owns
series-related cleanup such as queued extension jobs.

## Consequences
Deleting a workout permanently deletes its recurring series and generated
scheduled classes. Existing booked members and assigned athletes are still
notified through the existing post-delete notification flow.

## Implementation Notes
The Scheduling store now exposes `delete_class_series_for_workout/1`, cancels
queued class-series extension jobs for matching series, and deletes those series
inside the workout hard-delete workflow. A migration replaces the restrictive
`class_series.master_workout_id` foreign key with `ON DELETE DELETE ALL`.
