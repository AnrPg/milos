# ADR-050: Structured Training Log Modification Patches
Date: 2026-07-17
Status: Accepted

## Context
Execution notes and finish-flow modifications were originally modeled as
exercise-level annotations. That was sufficient for simple "changed reps" or
"skipped exercise" cases, but it cannot describe what happens in real training:
a user may change the load for only set 2, substitute one interval, complete
extra work, or reduce reps for a single expanded row while leaving the rest of
the workout as prescribed.

The product needs a fast logging workflow that preserves the canonical workout,
the user's scale, and the exact actual deviations. Coaches and analytics need
typed modification facts rather than free-text notes.

## Decision
Treat workout modifications as structured patch records attached to the
execution aggregate. A patch targets a concrete expanded workout instance, not
only an authored exercise definition.

Each patch stores:

- a stable `patch_id`
- target coordinates such as `section_id`, `segment_key`, `exercise_id`,
  `set_index`, `round_index`, and `field`
- `canonical_value` and `actual_value`
- a semantic `type`
- optional display labels and notes

The frontend modification step renders the prescribed workout expanded into
concrete performed rows. Editable values map to the same parameter concepts the
admin can set during workout authoring. Clicking a value opens an inline editor;
blur or enter commits a patch for that exact row and field.

The existing `POST /api/executions/:id/modifications` endpoint remains the write
boundary, but its OpenAPI schema is tightened to accept structured patches. The
execution response includes `exercise_modifications` so clients can preview and
continue saved changes.

## Rationale
The execution aggregate already owns workout completion facts, scores, notes,
and progress snapshots. Keeping structured patches on the aggregate avoids a
premature separate event-sourcing table while still giving analytics and coach
previews typed, queryable facts.

Instance coordinates are required because changing "squat reps" on one set
must not imply every squat row changed. A set/round/segment-aware target makes
the actual-workout delta reconstructable from the canonical materialized
workout.

## Alternatives Considered
Free-text "what changed" notes were rejected because they cannot power
analytics, coaching diff previews, or injury-aware checks.

Exercise-level modifications were rejected because they cannot distinguish set
1 from set 2 or a single interval from all repeated work.

A separate `training_logs` table was considered but deferred for this slice.
The execution aggregate already persists source relationships, completion
state, notes, scores, and modifications. A separate log table can be introduced
later if non-execution class logs require independent lifecycle states.

## Consequences
Clients must render and preserve stable expanded-row coordinates.

Patch validation must reject malformed coordinates and empty changes before
persisting.

Analytics can start consuming typed patch records from `workout_executions`, but
large-scale reporting may later need a projection table for efficient filtering
by field/type.

## Implementation Notes
Initial implementation on 2026-07-17.

- The required `vexp run_pipeline` tool from `AGENTS.md` was not exposed in this
  session, so discovery used targeted reads of the mandated docs, ADRs, and
  affected files.
- `exercise_modifications` now returns in normalized execution payloads.
- `POST /api/executions/:id/modifications` now accepts validated structured
  patches with concrete target coordinates and client-stable `patch_id` values.
- The execution finish wizard now renders collapsible prescribed sections with
  expanded per-set exercise rows. Inline value edits become patch records for
  the exact set/round/segment row.
- The in-execution quick Modify modal emits the same patch shape.
- The authenticated homepage exposes a sticky Log Workout / Resume Workout CTA,
  and execution-history detail previews structured actual-vs-prescribed
  modifications alongside notes.
- A standalone non-execution training-log aggregate remains TD-033 because it
  needs source selection, authorization, and gamification semantics that should
  not be hidden inside timer execution state.
- Verification: backend compile, `mix milos.architecture`, focused domain tests,
  frontend `pnpm type-check`, targeted ESLint, and OpenAPI regeneration passed.
