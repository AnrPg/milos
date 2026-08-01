# ADR-075: Workout Presentation and Inline Admin Editing
Date: 2026-08-01
Status: Accepted

## Context
Workout composition groups are persisted as repeated membership metadata, but the
interface currently presents that implementation detail on individual exercises.
Set counts, collapsed details, drag targets, authoring controls, and taxonomy filters
also vary between draft, published, admin, and member surfaces.

The admin user dossier currently routes editable finance facts to a separate
workspace under ADR-074. The product now requires those facts to be editable in
place and the dossier action density to be reduced. Library list/folder views,
recurring-series authoring, and private PDF exports also need presentation fixes.

## Decision
Composition groups are rendered as first-class presentation containers on every
workout surface. A group header owns its type and set count; member exercises retain
per-exercise repetitions and share a deterministic color accent. Group creation is
available only for selections of at least two exercises.

Structured exercise details start collapsed and expand on click, focus, or hover.
Repetitions remain in detailed editing only. Progressive load and deload controls
live in Advanced settings. Numeric editors retain an empty string while focused and
validate or normalize only on blur/submission. Cross-section dragging temporarily
opens a hovered destination and accepts the exercise drop.

Quick Text shows source line numbers. Its Structured/Quick Text mode control hides
while scrolling down and reappears on upward scroll, top-edge hover/focus, or when
near the top of the page.

The admin user dossier uses the existing owning-context mutations through inline
controls for editable facts. It does not add a parallel backend write model. This
supersedes ADR-074 only where that ADR requires editable dossier facts to deep-link
to another workspace. Redundant route actions are removed, membership information
is vertically ordered, and referrals, entitlements, and credits move into an
Advanced settings disclosure.

Workout folders omit synthetic parent-folder tiles. Folder actions use compact icon
controls. The workout library list mode uses rows and sortable, meaningful columns.
Class and workout type filters are absent for a single available type and collapsed
by default on non-admin surfaces when multiple types exist. Recurring class-series
creation does not select a workout; workouts will be associated with individual
dates in a later change.

Private PDF export continues through the shared local renderer. The renderer must
embed a Unicode-capable font, preserve human-readable labels, and maintain visible
spacing between section labels and titles. Missing optional package labels render as
empty content rather than punctuation placeholders.

## Rationale
Treating a composition group as a visible parent matches its execution semantics and
avoids repeating group-owned information. Shared interaction rules make authoring
predictable across mouse, touch, and keyboard use. Reusing canonical mutations keeps
inline dossier editing within existing bounded-context validation and authorization.

Conditional filters and quieter actions reduce controls that cannot affect the
result. A single Unicode-capable export renderer fixes every private document surface
without moving sensitive export generation to the server.

## Alternatives Considered
Repeating group labels and set counts on every exercise was rejected because it
misrepresents ownership and creates noisy cards.

Keeping all dossier edits as navigation links was rejected because it interrupts
small, contextual corrections and produces duplicate action clusters.

Adding dossier-specific backend mutations was rejected because it would duplicate
Finance and Identity validation paths.

Keeping numeric form state coerced to a minimum value on every keystroke was rejected
because intermediate empty input is a normal part of editing.

Keeping a workout selector on a recurring series was rejected because workout choice
will be date-specific and a series-level value would imply incorrect inheritance.

## Consequences
Workout renderers and editors must derive stable group boundaries from membership
metadata. Input components must distinguish transient display state from committed
numeric values. Hover expansion must preserve drag metadata and restore collapsed
state when appropriate.

Inline dossier controls must invalidate the same focused queries as their canonical
workspace counterparts and preserve role-based authorization. Removing the recurring
series workout selector changes the submitted contract only if the backend currently
requires that field; any such contract change must remain OpenAPI-first.

## Implementation Notes
Workout groups now render through shared parent presentations in structured
authoring, canonical Quick Text preview, published workout detail, execution,
and document export. The group header owns type and set count; children own reps
and use one deterministic accent. Quick Text-to-Structured hydration preserves
canonical `group_config.sets`, including after reload.

Structured exercise cards start collapsed, expose set details on hover or click,
and keep repetitions out of the compact row. Progressive load and deload editors
live in Advanced settings. Group actions require two selected exercises and use
visible button surfaces. Cross-section dragging expands the section rail, derives
the destination beneath the moving card from dnd-kit's movement stream, opens it
once per boundary crossing, and retains drag-start metadata through source unmount.

The Quick Text editor has a CSS-counter line-number gutter and an auto-hiding mode
bar that returns on scrolling or top-edge hover. Shared integer editors retain an
empty display value until blur, then normalize to their allowed minimum.

The admin dossier now stacks inline membership controls and moves credits,
entitlements, referrals, and rewards into Advanced settings. The workout library
has true rows, no synthetic parent folder, and compact folder icon actions. Type
filters suppress themselves for a single available type. Recurring series no
longer require a workout; the migration makes series occurrences nullable while
standalone slots still validate a workout. Generated OpenAPI artifacts reflect
that contract.

PDF export embeds DejaVu Sans and DejaVu Sans Bold for Unicode output, increases
section-label/title spacing, and humanizes package snapshots instead of printing
placeholder punctuation or machine codes.

Validation completed with frontend unit tests, lint, localization checks,
TypeScript, production build, backend compile and full tests, formatter, Credo,
the architecture boundary gate, a clean-database migration, and browser checks
covering grouped previews, line numbers, mode-bar behavior, inline membership
editing, conditional group controls, list/folder presentation, and recurring
series authoring. No new technical debt was deferred.
