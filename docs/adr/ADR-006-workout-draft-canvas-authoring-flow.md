# ADR-006: Workout Draft Canvas Authoring Flow
Date: 2026-06-07
Status: Accepted

## Context
Phase 2 shipped workout authoring as a single validated create request that
persisted the full workout tree in one operation. The approved workout canvas
design replaces that flow with a long-lived admin authoring surface that must
autosave partial state, support incomplete drafts, and publish only after a
separate validation pass.

The same redesign also expands the exercise prescription model beyond the
original `base_reps` and duration fields. The backend therefore needs a new
draft lifecycle, a more flexible exercise schema, and admin-only endpoints for
draft retrieval, autosave, and publish, while preserving the existing bounded
context and hexagonal architecture rules.

## Decision
Persist workout drafts on `master_workouts` using a `status` field and a
`draft_data` JSONB blob, then materialize validated sections, exercises, and
variations only when the admin publishes the draft.

## Rationale
Storing draft edits as a raw blob supports the canvas autosave model without
forcing the backend to validate partial user input on every debounce cycle.
That keeps the UI responsive and lets the publish step remain the only hard
validation gate.

Using `status` on the existing `master_workouts` record keeps draft and
published workouts under one identity, which makes reopening published workouts
for editing straightforward and allows the admin list to expose draft badges
without introducing a second authoring table.

Replacing the old exercise prescription fields with a normalized
`sets/prescription_value/prescription_unit/load_value/load_mode` model aligns
the persistence layer with the approved canvas interaction model, scale
variations, and preview materialization rules.

## Alternatives Considered
Keeping the one-shot create endpoint and validating every autosave payload was
rejected because it would force incomplete drafts into premature error states
and would not match the approved authoring UX.

Creating a separate drafts table was rejected because it would duplicate
identity, publication, and listing logic for an entity that is still the same
workout through different lifecycle states.

Persisting published sections and exercises eagerly on every autosave was
rejected because it would require destructive synchronization logic for partial
trees and would complicate validation, ordering, and rollback.

## Consequences
Admin workout APIs must distinguish between draft retrieval and member-facing
published workout retrieval.

The workouts infrastructure adapter must support draft creation, draft update,
and publish as separate operations while keeping `Repo` access inside the
owning context.

Publish becomes the point where full validation, scale-level binding, and tree
materialization happen. Draft autosave intentionally accepts structurally
incomplete content.

The new exercise schema introduces a compatibility break for any tests or code
still using `base_reps`, `base_duration_seconds`, or variation `reps` fields.

## Implementation Notes
The backend now persists draft workouts on `master_workouts` with `status` and
`draft_data`, exposes draft autosave and publish endpoints for the admin
canvas, and materializes published sections, exercises, and variations from the
draft blob during publish.

The frontend now uses a dedicated Zustand authoring store and a three-panel
canvas on `/admin/workouts/new`, with debounced autosave, live preview, scale
variation editing, and a mobile drill-down layout.

Desktop section sorting and in-section exercise sorting shipped as planned.
Cross-section exercise drag on desktop was deferred; the current release
supports cross-section moves through the advanced panel's explicit "Move to
section" action, which also covers mobile.
