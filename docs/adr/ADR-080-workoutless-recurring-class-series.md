# ADR-080: Workoutless recurring class series
Date: 2026-08-02
Status: Accepted

## Context
Recurring class series represent durable schedule intent: class type, name, time,
capacity, booking policy, and recurrence rule. Some class series are planned
before a WOD is selected, and some classes never need a stored master workout at
all. The database recently required `class_series.master_workout_id`, which made
series creation fail when admins created schedule-only recurring classes.

## Decision
Recurring class series may omit `master_workout_id`. Generated occurrences inherit
the optional value, so a recurring occurrence can also be schedule-only. One-off
scheduled classes continue to require a workout unless they belong to a series.

## Rationale
The series aggregate is primarily a scheduling construct. Requiring a workout at
series creation couples class cadence to programming readiness and blocks valid
schedule-first workflows. Keeping one-off classes strict preserves the existing
single-slot programming contract while allowing series to materialize shells that
can be programmed later.

## Alternatives Considered
Requiring admins to create placeholder workouts was rejected because it pollutes
the workout library and turns a scheduling action into programming busywork.

Keeping the database column non-null and adding a hidden default workout was
rejected because it would create misleading class previews and execution sources.

Deleting a series when an optional linked workout is deleted was rejected as a
database default because the schedule can remain valid without that workout.

## Consequences
Schedule reads and frontend previews must tolerate `workout: null` for recurring
classes. Calendar and booking flows continue to use the class name, type, duration,
and scheduled time even when no workout is attached.

This supersedes the ADR-079 assumption that recurring series require a workout.

## Implementation Notes
The `class_series.master_workout_id` column is now nullable and its foreign key
nilifies on direct workout deletion. The existing generated-occurrence changeset
already permits `master_workout_id` to be nil when `class_series_id` is present,
so no additional occurrence validation change was needed.
