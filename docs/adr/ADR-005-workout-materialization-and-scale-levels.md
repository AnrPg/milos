# ADR-005: Workout Materialization and Admin-Managed Scale Levels
Date: 2026-06-05
Status: Accepted

## Context
Phase 2 introduces the workout authoring model, scale-specific exercise
variations, and the materialization logic that turns a master workout into
scale-specific workout instances. The implementation plan proposes
query-time materialization from a base workout plus exercise variations, but
the open item in the design doc originally assumed a fixed set of canonical
scale labels chosen before the first migration.

The human-approved decision for this phase changes that assumption: scale
levels must be configurable by admins and may be added, renamed, reordered,
or removed over time, while still applying uniformly across the app.

## Decision
Materialize workout scale instances at query time from a single master
workout definition, and persist scale levels as admin-managed records rather
than as a fixed enum on `exercise_variations` or `workout_executions`.

## Rationale
Query-time materialization keeps one source of truth for workout content and
avoids synchronizing precomputed scale-specific copies whenever a workout or
variation changes. That matches the design doc’s materialization model and
keeps the domain logic pure.

Admin-managed scale levels satisfy the approved product requirement that the
labels are not permanent. Persisting scale levels in their own table allows
uniform naming, ordering, and active/inactive state across workout authoring,
materialization, browsing, and execution without hardcoding values in the
database schema or application code.

Using a stable `slug` per scale level lets the system store references
durably while allowing display labels to be renamed later without data
migrations.

## Alternatives Considered
Pre-materialized workout instances per scale were rejected because they would
duplicate workout structure, complicate updates, and create consistency risks
when the base workout changes.

A fixed enum for scale levels was rejected because it conflicts with the
approved requirement that admins can add, rename, or remove scale levels
without another schema migration.

Storing free-form scale labels directly on each variation was rejected
because it would not guarantee a single canonical app-wide scale taxonomy and
would make filtering, ordering, and validation inconsistent.

## Consequences
The workouts context must manage a new `scale_levels` entity and validate
exercise variations against active scale levels.

Materialization queries must load the workout tree together with variation
scale-level metadata before invoking the pure domain materializer.

Other contexts that persist scale-level references should store a stable
identifier derived from the scale-level record rather than an Ecto enum.

Admin removal of a scale level must be guarded by referential checks or by an
archive/deactivate path so historical data and existing workout variations do
not break.

## Implementation Notes
Phase 2 implementation stores scale levels in a dedicated `scale_levels`
table with a unique `slug`, human-readable `label`, `sort_order`, and
`is_active` flag. Exercise variations reference `scale_levels.id`, while the
domain materializer works on normalized plain maps containing the scale
level's slug and label.

The implementation plan’s Phase 2 checklist says “Write ADR-003”, but ADR-003
and ADR-004 already exist from Phase 1. This phase therefore uses ADR-005 to
keep numbering monotonic.

Scale-level replacement is implemented as a guarded full-list update from the
admin API. Existing scale levels can be relabeled and reordered in place by
their stable slug. Removal is blocked if any workout variation still
references the scale level, which avoids breaking historical or published
workout content.

The backend now exposes `GET/PUT /api/admin/scale-levels`,
`GET/POST /api/admin/workouts`, `GET /api/workouts/:id`, and
`GET /api/workouts/:id/scales`, with the OpenAPI artifacts regenerated for the
web app. The web admin surface includes scale-level management, workout list
view, workout creation, and client-side preview of materialized instances.

The early Phase 2 implementation briefly shipped before the broader
authenticated web shell was fully wired. That transitional note is now
obsolete: the admin workouts surface runs inside the shared authenticated web
shell and no longer relies on a separate in-memory-only login path.

On 2026-06-06, Phase 2 was hardened so workout section order and exercise order
are derived from authoring list position rather than trusting caller-supplied
integers. This keeps ordering contiguous per workout/per section and aligns the
admin UI with the backend persistence rules.

The same hardening pass tightened access and integrity constraints around
workout authoring: member workout discovery endpoints are restricted to members
and admins, `master_workouts.created_by_id` is enforced as a real user foreign
key, section parent references must stay within the same workout, timer
configs are validated by timer type before persistence, and blank exercise
variations are rejected unless they actually override at least one base field.

On 2026-06-10, the authored workout tree was normalized to carry real
database-backed audit timestamps across sections, exercises, and variations.
`workout_exercises` now persists both `inserted_at` and `updated_at`, while
`workout_sections` and `exercise_variations` gained `updated_at`. This keeps
the Ecto schema shape aligned with the actual tables and supports future admin
audit/read-model use without relying on schema-only assumptions.
