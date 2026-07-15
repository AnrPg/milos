# ADR-012: Execution Score Snapshots and Authoring Audit Timestamps
Date: 2026-06-10
Status: Accepted

## Context
Phase 2 introduced workout authoring tables for sections, exercises, and
scale variations. The current implementation only persisted `inserted_at` for
sections and variations, and omitted timestamps entirely for exercises. That
left the schema shape inconsistent across the authored workout tree and made
it impossible to answer simple audit questions about when child records were
created or last changed.

Phase 4 introduced execution progress persistence, but the stored state only
covered timer lifecycle fields plus checked exercise identifiers. Final
section scores depended on explicit client-submitted `section_scores` during
completion. If the athlete completed a workout without entering a score, the
execution history could show an empty score list even when the timer and
checklist state were sufficient to infer a measured result. In-progress
executions also lacked a durable semantic snapshot of progress per section.

The system now needs a coherent answer for both concerns:

- authored workout child records should have real database-level audit
  timestamps, not schema-only assumptions
- execution persistence should retain semantic progress snapshots and derive
  a fallback final score automatically when a format can be measured from the
  timer/checklist state

## Decision
Add database-backed audit timestamps to workout authoring child tables and
persist execution progress as derived per-section score snapshots backed by
elapsed-time state, with manual completion scores treated as an optional
override rather than a required source of truth.

## Rationale
Workout sections, exercises, and variations are authored records that evolve
over time. Storing actual timestamps at the table level keeps Ecto schemas
honest, supports future admin audit surfaces, and avoids preload/query
failures caused by declaring fields that do not exist.

Execution scoring rules belong in a pure domain module because they depend on
workout format semantics rather than transport details. Persisting elapsed
state and derived snapshots lets the backend reconstruct meaningful progress
for recovery, history, and abrupt interruptions while keeping controllers
thin. Manual score entry remains useful for formats with coach-directed
adjustments or athlete-edited final results, but it is no longer the only way
to avoid blank history.

## Alternatives Considered
Leaving workout child tables without timestamps:
rejected because it preserves schema drift and blocks future audit/read-model
uses for authored workout changes.

Computing scores only on the frontend and sending them as final truth:
rejected because it couples scoring correctness to one client implementation,
provides no durable progress snapshots for interrupted sessions, and makes
history depend on optional user input.

Adding a separate execution-events table:
rejected because it is heavier than the current product needs and would push
the app toward event-sourcing patterns that the architecture explicitly avoids.

## Consequences
Workout authoring migrations must backfill timestamps for existing rows and
schemas must match the resulting table shape exactly.

Execution progress APIs now need to carry enough elapsed-time state for the
backend to derive semantic snapshots across pauses, resumes, and segment
transitions.

The execution domain owns format-aware scoring heuristics. Application
services orchestrate workout lookup and feed the pure scorer so cross-context
reads stay out of controllers.

Some formats still permit manual override at completion even when an automatic
measured value exists. That override becomes an explicit edit of the measured
default, not a required first entry.

## Implementation Notes
Implemented on 2026-06-10 with two additive migrations:

- workout authoring child tables now persist audit timestamps in the database
  rather than assuming them in Ecto schemas
- `workout_executions` now stores `total_elapsed_ms`, per-section elapsed
  maps, and per-segment cycle counters alongside the existing progress fields

Execution scoring is handled by a new pure domain module,
`MilosTraining.Execution.Domain.ProgressSnapshotter`, which derives:

- in-progress semantic snapshots for scoreable sections
- fallback final scores when the athlete completes a workout without entering a
  manual score
- manual-overrides-first final payloads when the athlete edits the measured
  default

The frontend now uses stable segment-scoped checklist step IDs, rolls repeatable
formats forward by incrementing per-segment cycle counts instead of treating
every completed checklist as the end of the segment, and prefills the score
modal with the measured value before redirect.

OpenAPI request contracts and generated web artifacts were regenerated to carry
the new elapsed/progress fields.
