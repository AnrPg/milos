# ADR-068: Structured Workout Set Composition
Date: 2026-07-31
Status: Accepted

## Context
The published workout model stores one exercise prescription with a single set
count, repetition value, and load. Draft JSON already carries an unpersisted
load-progression hint and a `superset_group_id`, but published responses,
materialization, execution, and presentation do not preserve or interpret those
concepts consistently.

Coaches need to author supersets, different prescriptions for each set,
progressive loading or deloading in kilograms or percent of one-repetition
maximum, arbitrary groups of alternating exercises, and headers mixed into a
set. Notes at section and exercise level must also survive publication and be
visible on every workout presentation surface.

The change must preserve existing draft and published workouts, the
draft-data/revision lifecycle from ADR-006 and ADR-031, query-time scale
materialization from ADR-005, and stable set coordinates used by execution
modification patches in ADR-050.

## Decision
Extend the existing ordered workout-exercise row as a backward-compatible
authored workout item:

- `item_type` distinguishes executable `exercise` rows from non-executable
  `header` rows.
- `set_prescriptions` stores a validated ordered list of concrete per-set
  prescription/load records. Missing lists are derived from the legacy
  `sets`, prescription, and load fields.
- `load_progression` persists the authoring intent with an explicit
  `increase` or `decrease` direction, a load mode of kilograms or percent 1RM,
  and either a linear step or explicit per-set values.
- `superset_group_id` identifies exercises performed together without rest as
  one composite set.
- `alternating_group_id` identifies two or more exercises whose sets are
  interleaved in authored order. It is independent of section timer format and
  supports groups larger than two.

Exercise variations may override per-set prescriptions and load progression,
but they do not change header or group structure. Section, exercise, header,
and variation notes are normalized into public workout maps and displayed
verbatim at presentation boundaries.

The API exposes the fields through closed reusable OpenAPI workout schemas.
Execution filters headers from actionable checklist steps, expands concrete
per-set values, and orders grouped work by set index: all members of a
superset/alternating group for set one, then all available members for set two,
and so on.

## Rationale
An additive extension avoids renaming or replacing the mature
`workout_exercises` table and keeps all existing foreign keys, execution
annotations, and modification-patch exercise coordinates valid. Explicit item
types prevent headers from being inferred from punctuation or naming
conventions.

Concrete per-set records are the durable truth needed by preview, execution,
and training-log modifications. Retaining load-progression intent lets the
authoring UI distinguish loading from deloading while still producing
deterministic set values.

Group identifiers model supersets and alternating sets as composition
properties rather than timer/section formats. UUID identities are stable across
reordering and naturally support more than two members.

## Alternatives Considered
A new hierarchy of workout-set and workout-set-item tables was considered. It
would be semantically pure, but would replace exercise identities across every
published workout, assignment, execution annotation, and modification patch.
That destructive migration is disproportionate when the existing ordered row
can be extended additively.

Keeping all new fields only in `draft_data` was rejected because published,
assigned, scheduled, execution, and history consumers would lose the
information.

Encoding per-set values in display strings or coach notes was rejected because
it cannot be validated, scaled, ordered, or consumed by execution and
analytics.

Representing alternating sets as another section timer format was rejected
because alternation is orthogonal to timing and may occur in for-time, untimed,
or other sections.

## Consequences
The persistence adapter and materializer must preserve the richer item shape,
and all WOD presentation surfaces must use group-aware rendering.

Legacy workouts remain valid and are presented as ordinary exercises with
derived uniform set prescriptions. New headers are stored in the historical
`workout_exercises` table for compatibility, so code must use `item_type`
rather than assuming every row is executable.

Superset and alternating groups must contain at least two executable rows.
Headers cannot belong to either group. A row cannot belong to both group types
in the initial implementation because that would make checklist ordering
ambiguous.

## Implementation Notes
Implemented as an additive migration on `workout_exercises` and
`exercise_variations`, with a pure `WorkoutSetComposer` validating and
expanding concrete set rows before publication. Draft autosave remains
permissive, while publish rejects malformed groups, header membership in
groups, and rows assigned to both grouping modes.

The authoring canvas now supports sortable headers, arbitrary multi-select
superset and alternating groups, concrete per-set prescriptions and notes, and
linear or explicit load progressions with increase/decrease direction in kg or
percent 1RM. Shared presentation, execution checklist, finish review, workout
history detail, and document export adapters consume the same structured
fields. Execution omits headers from checkable work and interleaves grouped
members by set index.

OpenAPI workout objects were replaced with closed reusable schemas and the
TypeScript contract was regenerated. Live verification found and fixed an
existing `editor_session_id` compatibility omission in the new closed draft
schema, plus stale per-set units when changing progression mode. The final live
flow autosaved successfully and displayed a noted header, section note,
superset, three-member alternating group, `10/8/6` set prescriptions, and a
percent-1RM deload.

No work from this feature was deferred, so no technical-debt ledger entry was
added.
