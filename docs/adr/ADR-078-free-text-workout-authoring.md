# ADR-078: Free-text Workout Authoring
Date: 2026-08-02
Status: Accepted

## Context
Admins need a fast WOD authoring mode for writing the board as ordinary rich text.
This differs from Quick Text DSL: DSL is parsed and published into the canonical
structured workout model, while Free Text must remain intentionally unstructured.

Free-text WODs still need normal workout metadata for library, schedule, and
assignment flows. Athletes also need a useful clock in execution mode, but that
clock must be athlete-selected and must not imply structured workout parameters.

## Decision
Add `free_text` as the third workout authoring mode alongside `structured` and
`quick_text`.

Free-text workouts persist `free_text_body` and optional `free_text_document` on
`master_workouts`. Publication accepts a free-text workout without sections only
when the authoring mode is `free_text` and the body is not blank. Structured and
Quick Text publication keep the existing canonical section validation.

Display surfaces render free-text workouts as the stored body only, with no scale,
section, exercise, score, or prescription presentation. Execution uses a separate
manual timer surface where athletes choose an available timer format locally.

## Rationale
Separating Free Text from DSL prevents draft text that is meant only for display
from being parsed, canonicalized, or treated as failed structured data. Keeping
metadata on the same aggregate preserves existing schedule, assignment, library,
authorization, and deletion flows without a parallel workout table.

The local manual timer gives athletes practical execution support while preserving
the invariant that free-text content is unstructured.

## Alternatives Considered
Storing free text in `dsl_source` was rejected because DSL source has parse,
diagnostic, formatter, and publication semantics.

Creating a separate free-text workout table was rejected because every existing
consumer would need duplicate assignment and schedule integration.

Generating structured sections from rich text was rejected because this would turn
the feature into a parser and contradict the explicit one-piece text requirement.

## Consequences
Presentation and execution entry points must branch on `authoring_mode`. Any future
conversion from Free Text to Structured or DSL must be explicit and must not mutate
the original body implicitly.

## Implementation Notes
Implemented on 2026-08-02. Free-text persistence is additive and sectionless
publication is allowed only for nonblank `free_text_body`. The frontend adds a
third authoring tab with a Tiptap rich-text editor, text-only preview rendering,
and a local execution surface with selectable timer formats. No technical debt was
deferred.
