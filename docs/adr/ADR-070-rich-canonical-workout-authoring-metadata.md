# ADR-070: Rich canonical workout authoring metadata
Date: 2026-07-31
Status: Accepted

## Context

ADR-069 introduced Quick Text as a deterministic authoring interface over the
existing canonical workout aggregate. Completing that contract exposes
authoring concepts which the current published schema cannot retain: typed
notes, subtitles, planning metadata, exercise identity and capabilities,
distance and effort targets, typed rest, group presentation settings, and
scale-specific rich prescriptions.

Keeping those values only in `draft_data` would violate the one-canonical-model
decision because publication would discard information that the coach authored
and previewed. Creating a second Quick Text aggregate would create the same
divergence in a different form.

The existing workout execution contract must remain compatible. Its compact
columns (`sets`, `prescription_value`, `load_value`, timer configuration, and
concrete set prescriptions) are already consumed by materialization,
execution, history, and analytics.

## Decision

Extend the existing Workouts aggregate additively with two kinds of canonical
data:

1. frequently queried and execution-relevant values remain explicit typed
   columns;
2. strictly validated, versioned authoring metadata is retained in bounded
   JSON maps and typed-note arrays owned by the corresponding aggregate node.

`master_workouts` gains display/planning fields and typed notes.
`workout_sections` gains subtitle, typed notes, transition/rest metadata, and
validated section authoring metadata. `workout_exercises` gains stable catalog
reference, subtitle, typed notes, validated prescription metadata, and
validated group configuration. `exercise_variations` gains the corresponding
typed notes and prescription metadata.

Concrete set prescriptions remain the durable execution truth. Their bounded
metadata may retain per-set tempo, effort targets, distance, rest, and deload
intent without changing set coordinates.

The exercise catalog is a Workouts-owned canonical registry with stable string
identifiers, exact aliases, and supported prescription capabilities. Quick
Text publication resolves exact canonical names or registered aliases only.
It never performs fuzzy publication matching. The initial registry is
code-backed and versioned so authoring, parsing, documentation, and
autocomplete share one source; moving it to admin-managed persistence later
does not change workout references.

Composition groups continue using the existing superset/alternating UUID
membership columns. The DSL derives deterministic UUIDs from canonical
document coordinates and repeats one validated `group_config` on every member.
This preserves existing execution expansion while retaining title, set count,
rest, and presentation metadata.

## Rationale

An additive hybrid model preserves backward compatibility while preventing
loss of rich authored meaning. Explicit columns remain appropriate for fields
that are filtered, constrained, or executed frequently. Bounded maps avoid a
large migration for every exercise-specific coaching dimension, but unlike an
arbitrary metadata bag their keys and value types are enforced by the pure
domain vocabulary and canonicalizer.

A versioned code-backed exercise catalog provides stable identity and offline
autocomplete immediately without introducing a cross-context dependency or
requiring fuzzy matching. Deterministic group IDs keep parsing pure and
repeatable.

## Alternatives Considered

Keeping rich values only in Quick Text source was rejected because published
canonical workouts would lose behavior and display information.

Adding one nullable database column for every possible exercise capability was
rejected because many dimensions are sparse and exercise-specific, and adding
a new safe canonical key would require a migration even when no query or
execution behavior depends on it.

Using arbitrary unvalidated JSON was rejected because misspelled keys and
wrong value types would silently become published data.

Creating separate group and note aggregates was considered. It offers stronger
relational normalization but would require replacing the existing structured
set-composition and execution contracts. The additive representation retains
their semantics with a smaller, reversible migration.

Using Meilisearch as the exercise source of truth was rejected because search
indexes are projections, not canonical identity stores.

## Consequences

All write paths must validate bounded metadata before persistence. Read models,
OpenAPI schemas, duplication, materialization, and draft reconstruction must
round-trip the new fields.

Athlete-facing serializers must filter coach-only notes. Admin preview may see
all note types. Existing singular `note` columns remain compatibility
projections of the first applicable visible note until every consumer uses
typed notes.

Catalog changes require stable identifier and alias compatibility. Removing an
entry cannot invalidate an already published workout reference.

## Implementation Notes

Completed on 2026-07-31 as part of the two-phase Quick Text rollout.

- Additive migrations retain workout subtitle, difficulty, estimated duration,
  equipment, typed notes, workout metadata, section subtitle/notes/rest and
  metadata, exercise catalog references/subtitles/notes/prescription and group
  metadata, scale-level rich prescriptions, and bounded per-set metadata.
- `WorkoutAuthoringMetadata` validates the allowed keys, value shapes, typed
  note visibility, and size/capability limits before persistence. Empty
  default note arrays and metadata maps do not count as scale overrides.
- Existing explicit execution columns and concrete set prescriptions remain
  authoritative for runtime behavior. Rich maps retain sparse authoring intent
  without replacing queryable or execution-critical fields.
- The code-backed exercise catalog provides stable identifiers, exact aliases,
  capabilities, and autocomplete labels. Publication resolves only exact
  canonical names/aliases; fuzzy suggestions never become publication
  semantics.
- Composition groups receive deterministic coordinate-derived identifiers and
  repeat validated configuration on their existing membership representation.
- Materialization, duplication, draft reconstruction, serializers, OpenAPI,
  structured conversion, and Quick Text publication round-trip the new fields.
  Coach-only notes remain restricted to admin authoring responses.
- Migrations are additive and the legacy compact fields remain compatible with
  execution, history, analytics, and existing structured workouts.

The exhaustive DSL round-trip, randomized prescription, timer dry-run,
controller/revision, frontend security, production-build, and desktop/mobile
Playwright results are recorded in ADR-069. No rich canonical metadata item
from this decision remains deferred.
