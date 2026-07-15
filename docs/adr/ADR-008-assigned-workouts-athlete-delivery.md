# ADR-008: Assigned Workouts Athlete Delivery
Date: 2026-06-08
Status: Accepted

## Context
Phase 5 adds bespoke workout delivery for athlete users. An admin must be able
to assign one published master workout to one or more athletes for a specific
date, and athletes must then see those assignments in a week view without
exposing the member-oriented workout discovery flow.

The design doc places assigned workouts inside the Workouts bounded context and
defines a join table between assignments and athletes. The implementation also
has to respect the bounded-context rules: Workouts cannot import Identity
schemas directly, and cross-context reads should go through public APIs or an
Application Service.

## Decision
Represent each admin assignment as one `assigned_workouts` record plus one row
per athlete in `assigned_workout_athletes`, and expose week-view reads through
an Application Service that enriches workout-owned assignment data with athlete
identity details only when the caller is an admin.

## Rationale
The join-table model matches the approved data model and lets one admin action
target many athletes without duplicating the assignment payload or admin notes.

Keeping the assignment write inside the Workouts context preserves ownership of
workout-to-athlete delivery while leaving athlete validation to the
Application layer, which can call Identity through its public API without
cross-importing schemas.

Using an Application Service for week-view assembly keeps controller logic thin
and allows the same endpoint contract to serve both athlete self-service views
and admin oversight views with appropriately enriched data.

## Alternatives Considered
Creating one assignment row per athlete was rejected because it duplicates the
same schedule date and notes for a single admin action and makes later bulk
edits harder.

Joining directly against the Identity `User` schema inside Workouts was
rejected because it would violate the bounded-context rule against
cross-context schema imports.

Implementing admin and athlete week views as separate persistence models was
rejected because the underlying source of truth is the same assignment set and
only the presentation differs.

## Consequences
Phase 5 introduces new workout-owned persistence for assignment headers and
athlete links.

The Workouts API surface expands with assignment commands and queries, while
Identity remains the authority for athlete role validation and nickname data.

Admin assignment creation now depends on a preflight validation step that
filters the selected user ids to real athletes before the Workouts write runs.

## Implementation Notes
Phase 5 adds `assigned_workouts` and `assigned_workout_athletes` tables inside
the Workouts context, with one assignment header row per admin action and one
join row per athlete recipient.

Assignment creation now runs through `MilosTraining.Application.AssignWorkout`,
which validates the selected ids through Identity before delegating the write
to the Workouts context. That keeps athlete-role checks outside Workouts while
preserving workout-owned persistence.

Week-view reads now run through
`MilosTraining.Application.GetAssignedWorkoutWeek`. Athletes receive only their
own assignments, while admins receive the full week plus athlete nicknames
attached as plain maps. The Workouts query returns workout-owned assignment
data only; Identity enrichment happens in the Application layer.

The web app now exposes `/my-workouts` for athletes and admins plus
`/admin/workouts/[id]/assign` for assignment creation. With Phase 4 execution
mode now available, assigned-workout cards can also start a real workout
execution using the same fullscreen flow and execution store bootstrap used by
the self-selected workout experience.

Assigned-workout headers are now unique per
`(master_workout_id, scheduled_for, admin_notes)`, with blank notes normalized
to `NULL`. Repeated admin assignment requests merge only when the workout,
scheduled date, and effective coaching note are identical, so different note
variants can coexist for the same workout/date without collapsing distinct
programming intent into one shared header. A follow-up normalization migration
also trims legacy notes, rewrites blank strings to `NULL`, and consolidates any
historical duplicate headers that are only different by blank-note encoding.

Admins can now inline edit assignments from `/my-workouts` by changing the
scheduled date, athlete recipients, and admin notes. The inline edit API and
UI now keep the workout template fixed instead of rendering a misleading
reassignment control; assigning a different workout still starts from the
workout library, which matches the “assign new workout” path in the spec. When
an edit would otherwise collide with an existing header for the same workout,
date, and effective coaching note, the backend now consolidates the two headers
by merging athlete recipients instead of forcing the admin through a manual
delete-and-recreate workflow.

The athlete-facing `/my-workouts` response now strips admin-only recipient
metadata and returns a base-workout preview shape without scale variations or
available-scale metadata. That keeps the endpoint aligned with the “no scale
selection” rule for athlete assignments and avoids leaking authoring-oriented
data into the athlete flow.
