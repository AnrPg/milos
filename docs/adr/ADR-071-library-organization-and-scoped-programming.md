# ADR-071: Library organization and scoped programming
Date: 2026-07-31
Status: Accepted

## Context
Coaches need a faster way to organize the shared workout library and prescribe from a
user's calendar. Existing athlete assignments reference published master workouts,
which means editing an assigned workout can affect every other use of that workout.
Members, meanwhile, receive training through scheduled classes rather than direct
workout assignments.

The scheduling editor also repeats the same class configuration and makes recurring
class creation unnecessarily slow.

## Decision
Add admin-managed nested workout folders. A published workout belongs to zero or one
folder and remains visible in the normal workout library; folders are an organization
and presentation concern, not an access boundary. The library offers folder, tile,
and sortable-list views over the same records.

When a coach programs from a user profile, an existing workout is duplicated before
it is associated with the selected day. The duplicate remains visible in the normal
library and is saved in the folder selected by the coach. Its source workout is
recorded for provenance, while subsequent edits affect only the duplicate.

For athletes, the duplicate is assigned through the existing athlete-assignment
model. For members, the duplicate is associated with the selected scheduled class;
members do not receive direct assignments in this iteration.

Scheduling owns global defaults for capacity, booking timeout, and auto-approval.
They prefill new-slot forms but do not change existing slots. Durable recurring
class-series behavior, including timezone-aware expansion, is specified separately
in ADR-073.

## Rationale
Nested folders let coaches mirror their real programming library while preserving a
single workout record and a single normal library surface.

Copy-on-programming preserves a stable library template and makes athlete or
class-specific edits safe. Keeping copies visible in the library follows the product
requirement that coaches select their saved location, while source provenance makes
the relationship understandable.

Using the existing assignment and class-slot associations preserves bounded-context
ownership: Workouts owns workout copies and athlete assignments; Scheduling owns
class associations and slot defaults. An Application Service coordinates the
cross-context member flow.

## Alternatives Considered
Keeping personal copies in a private library was rejected because coaches explicitly
need to choose a normal library folder for the saved WOD.

Editing the selected source workout in place was rejected because it changes other
assignments and classes unexpectedly.

Direct member workout assignments were rejected for now because members are modeled
as class-booking users; personalized member programming remains a future product
decision.

Generating recurring slots solely in the browser was rejected because validation,
defaults, durable recurrence intent, and all-or-nothing behavior must be
authoritative on the backend.

## Consequences
The Workouts aggregate needs additive folder and source-workout persistence, folder
commands/queries, cycle-safe reparenting, and OpenAPI contracts. Existing workouts
remain valid and can be uncategorized.

Profile-calendar programming needs dedicated Application Services, authorization,
and read models assembled from public Identity, Workouts, and Scheduling APIs.

The batch UI is intentionally a compact “Create series” form: workout, class type,
weekdays, date range, time, and a preview count. It uses configured defaults unless
the coach expands an optional settings disclosure.

## Implementation Notes
Implemented additive `workout_folders`, `master_workouts.folder_id`, and
`master_workouts.source_workout_id` persistence. Folder deletion reparents child
folders and workouts to the deleted folder's parent, while cycle checks reject an
invalid nested hierarchy.

The admin workout library now exposes folder, tile, and sortable list modes, nested
path labels, folder filtering, and per-workout folder moves. Workout copies remain
normal visible library records and preserve source provenance.

The admin user profile now contains a role-specific weekly programming surface.
Athletes see assignments and receive the same newly-created WOD or an isolated copy
of an existing WOD. Members see only their booked classes and can only attach the
isolated copy to a class they actually booked on the selected day. The Application
Service validates that booking before copying, preventing orphan copies for an
invalid member target. A false-preserving parameter lookup was required so
`copy_source: false` does not accidentally enter the copy branch.

Scheduling defaults are persisted in Scheduling and prefill both one-off class and
series forms. Controller integration tests cover nested folders, metadata moves,
member booking isolation, athlete new-WOD assignment, defaults, and series creation.
