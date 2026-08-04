# ADR-082: Free-text execution modification notes
Date: 2026-08-03
Status: Accepted

## Context
ADR-050 models structured workout modifications as typed patches against concrete
expanded exercise rows. ADR-078 intentionally keeps free-text workouts
unstructured, so they have no section, exercise, set, or prescription coordinates
that the structured modification editor can safely target.

The finish wizard must nevertheless let an athlete record how a free-text WOD was
changed, persist that entry with the execution, and present it later without
inventing structured workout facts.

## Decision
Store a free-text WOD modification as one execution-owned modification patch with
`field: "note"`, `type: "other"`, the reserved `section_id: "free_text"`, an empty
canonical value, and the athlete's complete note as `actual_value`.

The finish wizard renders a multiline textarea for this mode. Presentation and
export surfaces recognize this patch shape and render `actual_value` verbatim as
pre-wrapped blob text. Structured workouts keep the row-targeted patch workflow
from ADR-050 unchanged.

## Rationale
The existing execution aggregate and modification endpoint already own actual-WOD
changes. Reusing that boundary avoids a parallel persistence path while the
reserved shape makes the absence of exercise coordinates explicit and
machine-detectable.

Keeping the complete note in `actual_value` preserves the canonical-versus-actual
patch contract and allows existing API clients to round-trip it. Rendering it as
blob text matches the intentionally unstructured source workout.

## Alternatives Considered
Fabricating an exercise row was rejected because a free-text workout has no
canonical exercise identity.

Using exercise annotations was rejected because they require selected source text
and describe annotations rather than whole-workout deviations.

Adding a dedicated database column was rejected because the existing JSONB
modification collection already owns this execution fact and supports the required
text size.

## Consequences
Modification validation permits an absent `exercise_id` only for the reserved
free-text note shape (in addition to the existing section-level sets case).

Analytics must treat this patch as unstructured text and must not infer exercise,
set, load, or repetition facts from it.

## Implementation Notes
Implemented the reserved free-text note patch in the execution modification
validator, allowing `exercise_id` to be absent only for `field: "note"` with
`section_id: "free_text"` and the existing section-level `sets` case.

The free-text finish wizard now renders a notes textarea on the modifications
step, reloads existing execution modifications when recovering an active
execution, saves the note through the existing execution modification endpoint
before completing the WOD, and renders the saved note as pre-wrapped blob text in
the confirmation step, workout history details, and document export.

The UI suffix regression was fixed by replacing the old generated plural suffix
key (`sa0f1490`) with ICU count messages across the affected web surfaces and all
locale catalogs. The visible `Ui.sa0f1490` text was a missing translation key,
not user-authored workout data.

Verification covered the backend domain validator, the DB-backed application
service persistence path, the free-text finish wizard component flow, i18n
catalog validation, type-checking, formatting, architecture boundaries, and a
production web build. Full live browser verification was intentionally skipped
per human instruction on 2026-08-03.
