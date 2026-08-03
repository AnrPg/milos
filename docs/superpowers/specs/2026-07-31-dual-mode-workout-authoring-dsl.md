# Dual-Mode Workout Authoring and Canonical Workout DSL

**Date:** 2026-07-31  
**Status:** Draft for product and architecture review  
**Scope:** Admin workout authoring, parsing, validation, canonical formatting,
editor assistance, autocomplete, publication, and coach documentation

---

## 1. Executive Summary

Milos Training will support two workout-authoring modes:

1. **Structured mode:** the existing visual, form-like workout canvas.
2. **Quick Text mode:** a familiar document editor backed by a small,
   workout-specific domain language.

The two modes are not separate workout models. They are two authoring
interfaces over the same canonical workout schema.

```text
Structured Canvas ────────────────────────────┐
                                              ▼
                                      Canonical Workout
                                              ▲
Quick Text → Parse → Validate → Canonicalize ─┘
                   │
                   └── diagnostics and suggested corrections

Canonical Workout → Canonical Formatter → Beautified text and workout preview
```

The structured workout is the ground truth. Quick Text is an authoring
convenience. A Quick Text draft cannot be published until it parses
deterministically and passes the same domain validation as the structured
canvas.

Quick Text is deliberately not arbitrary natural language. It uses a richer,
reasonably strict, line-oriented workout DSL with:

- canonical section formats;
- canonical workout, section, exercise, set, load, rest, scoring, scaling, and
  execution vocabulary;
- explicit scope markers;
- explicit note and header markers;
- deterministic progressive-load and deload notation;
- concrete per-set notation for arbitrary progressions;
- contextual autocomplete similar to VS Code;
- exercise-name and common workout-word suggestions;
- live syntax and semantic diagnostics;
- templates and inline documentation;
- a canonical pretty-printer that produces the expected, beautified form.

The application must never require the coach to think like a programmer. The
product-facing name should be **Quick Text**, **Workout Writer**, or another
plain-language label. “DSL”, “parser”, “AST”, and similar implementation terms
belong in engineering documentation, not in the coach-facing interface.

---

## 2. Product Premise

The coach is not expected to know programming, backend architecture, JSON, or
formal grammars. Quick Text should feel like a focused version of Microsoft
Word or Google Docs:

- click and type;
- use a conventional formatting toolbar;
- paste text;
- use headings and lists;
- undo and redo;
- navigate entirely by keyboard if desired;
- receive suggestions while typing;
- insert common workout structures from a slash menu;
- see mistakes explained in ordinary language;
- preview the final workout before publishing.

Tiptap is the recommended editor foundation because it can provide this
familiar surface while retaining a schema-driven document model and supporting
custom semantic nodes. Introducing it is a new external dependency and
therefore requires explicit human approval and an ADR before implementation,
as required by `AGENTS.md`.

The coach should not need to memorize the full language. The manual exists for
learning and reference, while autocomplete, templates, snippets, field-aware
suggestions, and live diagnostics make the language discoverable during use.

---

## 3. Authoritative Design Decisions

### 3.1 One canonical workout model

The canonical workout schema is the sole published representation. Structured
mode writes it directly through the established draft/publish lifecycle. Quick
Text parses into the same representation.

The system must not introduce:

- a second “text workout” aggregate;
- a less capable assignment-only workout model;
- published workouts whose execution depends on reparsing display text;
- natural-language text as the source of truth;
- separate validation rules for the two authoring modes.

### 3.2 Quick Text is an input format

The DSL source is an editable draft artifact. It may be retained so the coach
can resume authoring, but the published workout is always the validated,
materialized canonical workout.

### 3.3 Deterministic parsing

The core parser is deterministic. Correct syntax must always produce the same
canonical result.

AI is not required for parsing and must never silently determine publication
semantics. A future AI assistant may propose DSL text or corrections, but its
output must still pass the ordinary parser and domain validator and must be
accepted explicitly by the coach.

### 3.4 Ambiguity is an error

The parser must not guess when more than one valid interpretation exists.
Instead, it returns a diagnostic with:

- the affected source range;
- the reason;
- allowed alternatives;
- a suggested correction where one is safe;
- a link to the relevant help entry.

### 3.5 Canonical formatting

Beautification is produced from the canonical workout:

```text
DSL source
→ parse
→ canonical workout draft
→ canonical formatter
→ beautified DSL and visual preview
```

The formatter never “cleans up” unknown source and pretends that parsing
succeeded. It formats only a valid canonical model.

The principal round-trip invariant is:

```text
parse(format(canonical_workout)) == canonical_workout
```

### 3.6 Format-by-format completeness

Every supported section format must be specified, implemented, tested, and
documented separately. There is no generic fallback that attempts to interpret
an unknown structure.

### 3.7 Stable canonical vocabulary

Canonical DSL keywords, enum values, unit identifiers, section-format
identifiers, and parameter names are stable machine values. They are not
translated in storage.

The UI may show localized descriptions and help text, but parsing and
serialization use stable canonical tokens. User-authored titles, subtitles,
descriptions, and notes remain verbatim.

---

## 4. Relationship to Existing Architecture

This specification extends, rather than replaces, the following accepted
decisions:

- ADR-005: query-time workout materialization and admin-managed scale levels;
- ADR-006: durable draft data, autosave, explicit validation, and publish;
- ADR-009: format-aware workout execution and timer sequence construction;
- ADR-012: format-aware scoring snapshots and authoring timestamps;
- ADR-031: published workouts remain available while a new revision is edited;
- ADR-039: one reusable authoring workflow, including embedded assignment;
- ADR-045 and ADR-048: stable semantic values and localization at presentation
  boundaries;
- ADR-050: stable concrete set/round/segment coordinates for execution patches;
- ADR-068: headers, concrete per-set prescriptions, load progression,
  supersets, alternating groups, and notes.

### 4.1 Architectural ownership

The feature belongs primarily to the `Workouts` bounded context.

```text
Interface
  Phoenix controllers and Next.js/Tiptap editor

Application
  Parse/validate/preview/finalize orchestration where an operation crosses
  boundaries or coordinates several domain operations

Domain
  Pure DSL lexer/parser, canonicalizer, validator, format registry,
  progression expansion, canonical formatter

Infrastructure
  Draft persistence, exercise-catalog lookup adapters, search/index adapters
```

The parser, validator, canonicalizer, progression expansion, and formatter
must remain pure domain logic. They must not import Ecto, Phoenix, HTTP, Redis,
Meilisearch, Tiptap, or browser APIs.

The frontend may provide immediate parsing and diagnostics for responsiveness,
but the backend must perform authoritative parsing and validation at preview
and publish boundaries. If parser logic exists in both runtimes, parity must be
guaranteed through a shared grammar artifact and a shared conformance corpus.
An architecture ADR must decide whether to:

- keep the authoritative parser in Elixir and use a lightweight frontend parser
  only for editor assistance;
- generate parsers for both runtimes from one grammar;
- use another implementation that preserves domain purity and exact parity.

### 4.2 Contract-first API

Any new preview, parse, validation, suggestion, or publication endpoint must be
specified in OpenAPI before its controller is implemented. Generated frontend
clients remain read-only.

### 4.3 Existing draft lifecycle

Quick Text should reuse the existing durable draft and revision behavior:

- partial or invalid source can be autosaved;
- the last valid canonical preview may be retained separately;
- invalid edits do not destroy the last valid parsed result;
- publication performs authoritative parsing and complete validation;
- the currently published revision remains live while a new revision is
  edited;
- embedded workout creation uses the same Quick Text mode and publication
  pipeline as standalone authoring.

---

## 5. Authoring Modes and Mode Switching

### 5.1 Structured mode

Structured mode remains the most explicit editor and direct representation of
canonical fields. It is the reference UI for:

- discovering all supported parameters;
- correcting complex validation errors;
- inspecting the exact parsed result;
- editing fields that are difficult to express concisely;
- reviewing scale-specific variations;
- reviewing materialized workout instances.

### 5.2 Quick Text mode

Quick Text provides efficient keyboard-first authoring while preserving the
same capabilities.

It must support:

- all canonical workout parameters;
- all canonical section parameters;
- all supported section formats;
- all canonical exercise parameters;
- headers and subtitles;
- notes at every supported scope;
- fixed and progressive set prescriptions;
- linear load progression and deload;
- arbitrary per-set load, reps, duration, or distance;
- supersets and alternating groups;
- scale variations;
- rest semantics;
- scoring semantics;
- timer and WOD settings.

### 5.3 Structured to Quick Text

Switching from Structured to Quick Text serializes the current canonical draft
with the canonical formatter. The generated result is guaranteed parseable and
becomes the Quick Text source.

### 5.4 Quick Text to Structured

Switching from Quick Text to Structured is allowed when:

1. the source is syntactically valid;
2. all canonical references resolve;
3. all domain validations pass;
4. the parsed result has no blocking diagnostics.

If blocking errors exist, the application remains in Quick Text and shows
exactly what must be corrected. The coach may still save the invalid source as
a draft.

### 5.5 Unsaved-mode conflict prevention

The application must not maintain two independently editable versions of the
same workout. At any moment, one mode owns the active draft state.

Mode switching performs an explicit conversion and updates the common draft
revision. Stale browser tabs and revision conflicts follow the existing workout
revision policy.

---

## 6. DSL Design Goals

The language should be:

- deterministic;
- expressive enough for every canonical workout;
- stricter than natural language;
- readable by a coach;
- writable without programming knowledge;
- line-oriented and easy to scan;
- friendly to incremental parsing;
- easy to autocomplete;
- easy to format canonically;
- compatible with copy/paste;
- safe to store as an incomplete draft;
- versioned;
- extensible without changing the meaning of older documents;
- independent of visual styling;
- localizable in explanations without localizing canonical tokens.

The language should not:

- accept prose and guess its intended structure;
- use formatting such as font size or color as the only source of semantics;
- allow arbitrary keys that the canonical model cannot store;
- silently discard unknown parameters;
- silently coerce invalid exercise/parameter combinations;
- allow cosmetic editor markup to alter workout meaning;
- require punctuation-heavy programming syntax;
- expose database IDs to the coach;
- encode executable meaning only inside notes.

---

## 7. Canonical Document Hierarchy and Scope

The DSL mirrors the canonical hierarchy:

```text
Workout
├── workout metadata
├── workout notes
└── ordered sections
    ├── section identity, title, subtitle, format, timer, score, and notes
    ├── optional nested sections
    └── ordered authored items
        ├── header
        ├── exercise
        │   ├── base prescription
        │   ├── concrete per-set prescriptions
        │   ├── progression intent
        │   ├── rest rules
        │   ├── execution parameters
        │   ├── notes
        │   └── scale variations
        ├── superset group
        └── alternating group
```

Every field has one defined scope. A parameter in the wrong scope is a
semantic validation error even if its syntax is otherwise valid.

Examples:

- `estimated-duration` is workout metadata.
- `time-cap` normally belongs to a section.
- `tempo` belongs to an exercise or a concrete set.
- `rest-between-rounds` belongs to a format that has rounds.
- `rest-between-sets` belongs to an exercise, group, or straight-set section,
  depending on the canonical rule.
- `score` belongs to a scoreable section.

Indentation may improve readability, but explicit block markers carry
structure. Meaning must not depend solely on spaces copied from an external
document.

---

## 8. Lexical and Serialization Rules

### 8.1 Encoding and lines

- Source is UTF-8.
- Canonical output uses one statement per line.
- Canonical output uses LF line endings.
- Tabs are normalized to spaces by the editor but are not semantically
  meaningful.
- Blank lines are allowed between logical blocks.
- Leading and trailing whitespace is ignored where unambiguous.

### 8.2 Canonical tokens

- Canonical keys use lowercase `kebab-case`.
- Canonical section formats use lowercase `kebab-case`.
- Canonical enum values use lowercase `kebab-case`.
- The formatter always emits canonical tokens.
- The parser may accept explicitly registered compatibility aliases, but it
  must never invent aliases heuristically.
- Deprecated aliases produce a non-blocking warning and a canonical
  replacement.

Examples:

```text
estimated-duration: 60 min
rest-between-sets: 2 min
target-rpe: 8
format: straight-sets
```

### 8.3 Delimiters

The proposed primary block markers are:

```text
[workout]
[/workout]

[section: FORMAT]
[/section]

[exercise: EXERCISE NAME]
[/exercise]

[header]
[/header]

[group: superset]
[/group]

[group: alternating]
[/group]

[scale: SCALE SLUG]
[/scale]
```

The exact surface grammar must be finalized in the phase ADR and grammar
specification. Explicit closing markers are recommended because they survive
copy/paste, do not rely on whitespace, and make parser recovery predictable.

### 8.4 Titles and subtitles

The canonical serializer uses explicit fields:

```text
title: Lower Body Strength
subtitle: Week 4 — Heavy Day
```

The editor may visually render the workout title as Heading 1 and the subtitle
as Heading 2. Their semantic identity comes from the corresponding Tiptap node
or DSL field, not merely from font size.

### 8.5 Comments

If source comments are supported, they must have a single explicit marker and
must never be published as workout notes. A proposed form is:

```text
// Draft reminder for the coach; not part of the workout.
```

Comments are authoring-only source. Notes are canonical workout data.

### 8.6 Strings and escaping

Most title and note values are plain text extending to the end of the line or
to the end of an explicit note block. Quoted strings are required only when a
value would otherwise collide with a closing marker or another reserved token.

The formatter owns escaping. The coach should rarely need to type escape
sequences manually.

### 8.7 Units

Units are canonical semantic tokens with registered display aliases.

Examples include:

- time: `ms`, `sec`, `min`, `hour`;
- load: `kg`, `lb`, `%1rm`;
- distance: `mm`, `cm`, `m`, `km`, `ft`, `yd`, `mi`;
- energy: `kcal`;
- count: `rep`, `round`, `set`;
- effort: `rpe`, `rir`;
- heart rate: `bpm`, `%hrmax`.

Canonicalization converts compatible input forms:

```text
2m
2 min
120 sec
```

to one canonical internal duration. The formatter emits the configured
canonical display form without changing meaning.

---

## 9. Full Illustrative Document

The following example demonstrates the intended expressiveness. It is a design
example; the final grammar and exact keys must be confirmed against the
canonical schema before implementation.

```text
[workout]
dsl-version: 1
title: Lower Body Strength and Conditioning
subtitle: Week 4 — Heavy Day
type: strength
difficulty: advanced
estimated-duration: 65 min
equipment: barbell, rack, kettlebell, rower
tags: strength, lower-body, progression

!note:
Focus on bracing, stable depth, and technically consistent repetitions.

!coach-note:
Reduce the final heavy set if warm-up velocity is substantially below normal.

[section: rounds]
title: Warm-up
subtitle: Move continuously at conversational pace
rounds: 3
rest-between-rounds: 45 sec

[exercise: Air Squat]
reps: 10
tempo: 3010
[/exercise]

[exercise: Glute Bridge]
reps: 12
[/exercise]

[exercise: Run]
distance: 200 m
pace: easy
[/exercise]
[/section]

[section: straight-sets]
title: Main Strength
subtitle: Back Squat
score: load
score-unit: kg

[header]
title: Build with perfect technique
subtitle: The final set is a deliberate deload
!note:
This header is displayed but does not become an executable checklist step.
[/header]

[exercise: Back Squat]
progression: explicit

sets:
- 5 reps @ 60 %1rm
- 5 reps @ 70 %1rm
- 3 reps @ 80 %1rm
- 3 reps @ 85 %1rm
- 5 reps @ 65 %1rm [deload]

tempo: 31X1
target-rpe: 8
rest-between-sets: 2 min 30 sec

!coach-note:
Stop the progression if technique deteriorates.

!athlete-note:
Record actual load and perceived effort after every working set.

[scale: beginner]
sets:
- 8 reps @ 45 %1rm
- 8 reps @ 50 %1rm
- 6 reps @ 55 %1rm
- 6 reps @ 60 %1rm
[/scale]
[/exercise]
[/section]

[section: emom]
title: Conditioning
duration: 12 min
interval: 1 min
score: completed-reps

[exercise: Kettlebell Swing]
interval-assignment: odd
reps: 10
load: 24 kg

!scaling-note:
Choose a load that permits an unbroken set with stable overhead control.
[/exercise]

[exercise: Burpee]
interval-assignment: even
reps: 8
[/exercise]

rest-before-next-section: 3 min
[/section]

[section: recovery]
title: Cooldown

[exercise: Hip Flexor Stretch]
duration: 30 sec
side: both
sets: 2
rest-between-sides: 10 sec
[/exercise]
[/section]
[/workout]
```

---

## 10. Workout-Level Parameters

The final registry must be generated from or validated against the canonical
schema. The expected categories include:

### 10.1 Identity and display

- `title`;
- `subtitle`;
- `description`;
- `type`;
- `difficulty`;
- `tags`;
- cover/display metadata where supported;
- coach-facing internal label where supported.

### 10.2 Planning

- `estimated-duration`;
- target population;
- training objective;
- required equipment;
- location or modality where canonical;
- week/day/program position where canonical;
- default scale;
- assignment-related defaults where they belong to Workouts.

### 10.3 Publication and compatibility

- `dsl-version`;
- source revision;
- canonical schema version;
- draft/publication metadata managed by the application rather than freely
  editable source where appropriate.

### 10.4 Workout notes

- general note;
- coach-only note;
- athlete-visible note;
- safety note;
- scaling note;
- equipment/setup note.

The DSL must not expose security-sensitive or server-owned fields such as
database IDs, creator IDs, audit timestamps, tenant IDs, or publication status
as ordinary editable text.

---

## 11. Notes, Headers, and Subtitles

### 11.1 Note markers

Notes require explicit type and scope.

Proposed markers:

```text
!note:
General authored information.

!coach-note:
Visible only to authorized coaches.

!athlete-note:
Visible to the athlete.

!safety-note:
Safety or stop-condition information.

!scaling-note:
Scaling guidance.

!equipment-note:
Setup and equipment guidance.
```

The allowed note types must be a canonical registry. Arbitrary note marker
names are rejected.

### 11.2 Scope

A note belongs to the closest open canonical block:

- directly within `[workout]`: workout note;
- directly within `[section: ...]`: section note;
- within `[exercise: ...]`: exercise note;
- within `[header]`: header note;
- within `[scale: ...]`: scale-variation note.

The formatter makes the scope visually unambiguous.

### 11.3 Multiline notes

The Tiptap document stores a note as a semantic block node. The textual
serialization uses the note marker followed by its block contents. The parser
must define an unambiguous termination rule, preferably the next canonical
statement or closing marker at the same scope.

Rich formatting inside notes may include:

- paragraphs;
- bold;
- italic;
- underline;
- inline links;
- bullet and numbered lists;
- safe callouts.

Formatting is presentation metadata and does not alter workout execution.

### 11.4 Headers

Headers are canonical non-executable authored items, consistent with ADR-068:

```text
[header]
title: Heavy Working Sets
subtitle: Maintain the same setup for every attempt

!note:
Displayed between exercise groups.
[/header]
```

Headers:

- retain stable authored identity internally;
- participate in authored ordering;
- are displayed in workout presentations;
- never become executable checklist steps;
- cannot belong to superset or alternating groups;
- may carry notes;
- must not be inferred from punctuation or all-capital text.

---

## 12. Canonical Section Formats

### 12.1 Registry rule

The accepted backend format registry is authoritative. The DSL formatter,
parser, autocomplete, templates, documentation, and tests must derive from or
be checked against the same registry so they cannot drift.

The existing execution architecture currently describes nineteen format
families. The
DSL design must cover the current canonical identifiers, including:

1. `untimed`;
2. `for-time`;
3. `train-to-exhaustion`;
4. `kcal-target`;
5. `emom`;
6. `complex-emom`;
7. `even-odd`;
8. `billat`;
9. `amrap`;
10. `edt`;
11. `death-by`;
12. `tabata`;
13. `custom-hiit`;
14. `cluster`;
15. `hrr`;
16. `ladder-ascending`;
17. `ladder-descending`;
18. `pyramid`;
19. `rest`.

If the current source registry differs, the source registry wins and this
table must be updated in the same design change. A generic `rounds` or
`straight-sets` authoring format may also exist as an authoring composition
format independent of timer type; the ADR must define whether these are true
section formats, aliases over `untimed`, or separate composition settings.

### 12.2 Per-format specification

Every format receives its own specification containing:

- canonical identifier;
- coach-facing name and description;
- required fields;
- optional fields;
- forbidden fields;
- body structure;
- allowed exercise/group structures;
- timer behavior;
- checklist expansion behavior;
- score behavior;
- rest behavior;
- examples;
- invalid examples;
- canonical formatter output;
- parser tests;
- validation tests;
- execution compatibility tests;
- documentation entry;
- autocomplete context.

### 12.3 Baseline format matrix

| Format | Required concepts | Typical optional concepts |
|---|---|---|
| `untimed` | ordered items | sets, progression, manual completion |
| `for-time` | work sequence | rounds, time cap, score |
| `train-to-exhaustion` | work sequence | rest, failure condition, score |
| `kcal-target` | target energy | time cap, equipment |
| `emom` | duration/rounds, interval | assignments, score |
| `complex-emom` | duration/rounds, interval slots | per-slot exercises |
| `even-odd` | duration/rounds, odd/even groups | interval length |
| `billat` | effort/rest intervals, rounds | pace/distance target |
| `amrap` | duration, work sequence | score, target rounds |
| `edt` | duration and paired work | PR-zone rounds, score |
| `death-by` | starting work, increment rule | cap, score |
| `tabata` | rounds, work, rest | stations, score |
| `custom-hiit` | work, rest, rounds | stations, transition |
| `cluster` | sets, cluster reps, intra-set rest | load, inter-set rest |
| `hrr` | effort phase, recovery condition | HR target/drop, cap |
| `ladder-ascending` | start and increment/end rule | duration/cap |
| `ladder-descending` | start and decrement/end rule | duration/cap |
| `pyramid` | ordered progression or peak rule | cap, load progression |
| `rest` | duration or recovery condition | notes, next-section transition |

This table is a discovery baseline, not a substitute for the detailed
format-by-format contract.

### 12.4 Expected canonical shape

Sections use a predictable format:

```text
[section: FORMAT]
title: ...
subtitle: ...

# required settings in canonical order
# optional settings in canonical order
# notes in canonical order
# authored items in authored order

[/section]
```

The formatter must use a stable field order for each format. This makes
documents easy to scan and gives coaches a repeatable writing pattern.

---

## 13. Exercise References and Parameters

### 13.1 Exercise identity

The visible source may contain:

```text
[exercise: Back Squat]
```

When selected from autocomplete, the Tiptap node should retain stable hidden
metadata:

```json
{
  "type": "exercise",
  "attrs": {
    "exerciseId": "stable-exercise-id",
    "label": "Back Squat"
  }
}
```

The coach sees ordinary text. The editor and parser retain unambiguous
identity. Renaming an exercise does not change its identity.

Plain pasted text without hidden metadata is resolved against the exercise
catalog:

- one exact canonical match: resolve automatically;
- one exact registered alias: resolve and warn if the alias is deprecated;
- several matches: require selection;
- no match: blocking unresolved-reference diagnostic.

The parser must never use approximate fuzzy matching to publish an exercise
identity without coach confirmation.

### 13.2 Expected exercise parameter registry

The canonical parameter registry may include:

- `sets`;
- `reps`;
- `duration`;
- `distance`;
- `load`;
- `load-mode`;
- `percentage-of`;
- `target-rpe`;
- `target-rir`;
- `tempo`;
- `pace`;
- `cadence`;
- `target-heart-rate`;
- `side`;
- `stance`;
- `grip`;
- `range-of-motion`;
- `height`;
- `incline`;
- `resistance`;
- `equipment`;
- `variation`;
- `interval-assignment`;
- `score-contribution`;
- `transition`;
- `rest-*`;
- `progression`;
- concrete per-set prescriptions;
- notes;
- scale-specific overrides;
- grouping identity managed by group blocks or stable hidden metadata.

This is a registry, not permission for every exercise to use every field.

### 13.3 Exercise capability validation

The exercise catalog should describe supported prescription dimensions.

Examples:

- `Run`: distance, duration, pace, incline, heart-rate target;
- `Back Squat`: reps, load, percentage, RPE, RIR, tempo, stance;
- `Plank`: duration and optional load, but not distance;
- `Stretch`: duration, side, intensity, and range;
- machine/cardio work: duration, distance, pace, cadence, calories, resistance.

This source is syntactically understandable:

```text
[exercise: Back Squat]
distance: 500 m
[/exercise]
```

It is nevertheless semantically invalid because `distance` is not a supported
Back Squat dimension.

---

## 14. Sets and Prescription Syntax

### 14.1 Uniform sets

Compact uniform form:

```text
sets: 5
reps: 3
load: 80 %1rm
```

The parser may accept a registered compact prescription:

```text
prescription: 5 x 3 @ 80 %1rm
```

The formatter should choose one canonical representation. Compact aliases are
input conveniences, not additional canonical models.

### 14.2 Equivalent typography

The normalizer may explicitly treat:

```text
5x3
5 x 3
5 × 3
```

as the same registered compact form. This tolerance must be defined, tested,
and limited. It must not expand into open-ended natural-language guessing.

### 14.3 Concrete per-set prescriptions

Concrete sets are the durable truth for execution:

```text
sets:
- 5 reps @ 60 %1rm
- 5 reps @ 70 %1rm
- 3 reps @ 80 %1rm
- 3 reps @ 85 %1rm
- 5 reps @ 65 %1rm [deload]
```

Each set may carry supported overrides:

```text
sets:
- 5 reps @ 60 %1rm; tempo: 31X1; target-rpe: 6
- 5 reps @ 70 %1rm; tempo: 31X1; target-rpe: 7
- 3 reps @ 80 %1rm; tempo: 31X1; target-rpe: 8
```

The final grammar should keep the common case concise while allowing an
expanded set block when several parameters differ.

### 14.4 Set coordinates

Concrete set order produces stable set indexes used by:

- execution expansion;
- actual-versus-prescribed modification patches;
- progress persistence;
- score derivation;
- analytics.

Formatting and reparsing must preserve set order and canonical identity rules.

---

## 15. Progressive Load and Deload

At least three canonical authoring forms are required.

### 15.1 Linear range

```text
progression: linear
sets: 5
reps: 5
load: 60 %1rm -> 80 %1rm
```

The parser validates that the range can produce the declared number of sets
according to the canonical interpolation rule.

### 15.2 Linear step

```text
progression: linear
sets: 5
reps: 5
load-start: 60 %1rm
load-step: +5 %1rm
```

Deload direction:

```text
progression: linear
sets: 5
reps: 5
load-start: 80 %1rm
load-step: -5 %1rm
```

### 15.3 Explicit arbitrary progression

```text
progression: explicit
sets:
- 5 reps @ 60 %1rm
- 5 reps @ 67.5 %1rm
- 3 reps @ 75 %1rm
- 3 reps @ 82.5 %1rm
- 5 reps @ 65 %1rm [deload]
```

The explicit form supports:

- arbitrary load increases;
- arbitrary decreases;
- a deload at any set;
- changing repetitions;
- changing duration;
- changing distance;
- changing tempo or effort targets where canonical;
- mixed progression strategies.

### 15.4 Intent and expanded truth

Consistent with ADR-068:

- concrete `set-prescriptions` are the durable execution truth;
- `load-progression` retains authoring intent;
- the canonicalizer expands a valid linear progression to concrete sets;
- materialization and execution consume concrete sets;
- the formatter may preserve and display progression intent when it can do so
  without losing concrete truth.

### 15.5 Progression validation

Validation includes:

- nonzero positive set count;
- matching number of concrete sets;
- compatible units throughout a progression;
- valid percent range;
- allowed precision and rounding policy;
- direction matching the declared intent;
- no unsupported mixed load modes;
- no impossible exercise capability;
- explicit handling of rounding when kilograms or pounds do not divide evenly;
- scale-variation progression compatibility.

---

## 16. Rest Semantics

A generic `rest` field is insufficient. Rest must be typed by when and where it
occurs.

Expected canonical keys include:

```text
rest-between-reps: 10 sec
rest-within-cluster: 20 sec
rest-between-sets: 2 min
rest-between-exercises: 30 sec
rest-between-rounds: 90 sec
rest-between-groups: 2 min
rest-between-sides: 10 sec
rest-after-exercise: 45 sec
rest-before-next-section: 3 min
transition-time: 15 sec
```

Conditional recovery may be supported only when the canonical model and
execution mode can represent it:

```text
rest-until: heart-rate < 120 bpm
rest-until: ready
rest-range: 2 min .. 3 min
```

Each format defines which rest types are:

- required;
- allowed;
- redundant;
- forbidden;
- inherited;
- overridden at group or exercise scope;
- translated into timer segments;
- displayed only as guidance.

For example, `rest-between-rounds` on a format without rounds should be a
semantic error rather than an ignored value.

Rest inheritance and precedence must be explicit. A proposed precedence is:

```text
concrete-set rest
> exercise rest
> group rest
> section rest
> no implicit rest
```

The final ADR must confirm this against execution semantics.

---

## 17. Supersets, Alternating Groups, and Headers

### 17.1 Superset

```text
[group: superset]
title: Upper Body A
sets: 4
rest-between-groups: 90 sec

[exercise: Bench Press]
reps: 8
load: 70 %1rm
[/exercise]

[exercise: Pull-up]
reps: 8
[/exercise]
[/group]
```

### 17.2 Alternating group

```text
[group: alternating]
title: Assistance Circuit
sets: 3

[exercise: Split Squat]
reps: 10
side: each
[/exercise]

[exercise: Dumbbell Row]
reps: 12
side: each
[/exercise]

[exercise: Pallof Press]
reps: 10
side: each
[/exercise]
[/group]
```

### 17.3 Canonical rules

Consistent with ADR-068:

- a group contains at least two executable exercises;
- groups may contain more than two exercises;
- a header cannot belong to a group;
- a row cannot simultaneously belong to both a superset and alternating group
  in the initial model;
- groups are composition semantics independent of section timer format;
- execution expands groups by concrete set index;
- scale variations may change prescriptions but not group structure.

Stable group IDs are hidden metadata. Coaches use group blocks and do not type
UUIDs.

---

## 18. Scale Variations

Scale levels are admin-managed canonical entities with stable slugs and
editable display labels, consistent with ADR-005.

Proposed syntax:

```text
[exercise: Pull-up]
reps: 8

[scale: beginner]
variation: Ring Row
reps: 10
[/scale]

[scale: advanced]
load: 10 kg
[/scale]
[/exercise]
```

Rules:

- autocomplete suggests active scale levels;
- hidden metadata may retain the stable scale-level ID;
- the canonical text uses the stable slug;
- display labels may be localized or renamed without changing the slug;
- an absent variation means inheritance from the base prescription;
- a variation must change at least one allowed value;
- variations may override concrete sets and progression where supported;
- variations cannot mutate header or group structure;
- inactive or removed scale references block publication or require an
  explicit migration choice.

The materialized preview must show Base plus every applicable scale instance
before publication.

---

## 19. Scoring, Timer, and WOD Settings

### 19.1 Scoring

Scoreable sections require an explicit canonical configuration:

```text
score: time
score-unit: min
score-label: Completion time
```

or:

```text
score: rounds-and-reps
score-unit: rounds+reps
```

Allowed score types and units are format-aware. The parser accepts canonical
values; the domain validator checks their compatibility.

### 19.2 Timer settings

Timer settings are selected by section format and may include:

- total duration;
- interval duration;
- rounds;
- work duration;
- rest duration;
- transition duration;
- time cap;
- auto/manual advancement policy where configurable;
- interval/station assignment;
- recovery condition;
- target completion condition.

The DSL does not allow a second independent timer type that contradicts the
section format.

### 19.3 Execution compatibility

A section is publishable only if the canonical execution engine can construct
its complete timer/checklist sequence. Parser success alone is insufficient.

Publication validation should include a dry construction of:

- ordered timer segments;
- executable checklist rows;
- group expansion;
- concrete set coordinates;
- score prompts/defaults;
- rest/transition segments.

---

## 20. Parsing Pipeline

The parsing pipeline is staged:

```text
Tiptap document or textual DSL
→ safe editor-document extraction
→ lexical normalization
→ tokenization
→ syntax parsing
→ unresolved canonical references
→ canonical draft AST
→ canonical reference resolution
→ progression expansion
→ domain validation
→ canonicalization
→ execution/materialization compatibility validation
→ valid canonical workout or structured diagnostics
```

### 20.1 Lexical normalization

Only explicitly safe equivalences are normalized:

- whitespace around operators;
- `x` and `×` in registered set notation;
- recognized unit aliases;
- Unicode normalization;
- line endings;
- registered case-insensitive canonical tokens;
- registered decimal separator policy;
- registered exercise aliases.

Normalization must preserve source spans so diagnostics point to the original
text.

### 20.2 Syntax parsing

The parser produces:

- block hierarchy;
- key/value statements;
- typed literal candidates;
- source spans;
- unresolved exercise/scale references;
- syntax diagnostics;
- recovery points so several errors can be shown at once.

### 20.3 Reference resolution

Reference resolution uses canonical registries:

- exercise catalog;
- active scale levels;
- section formats;
- units;
- score types;
- note types;
- exercise parameter keys;
- enum values;
- registered aliases.

Fuzzy search may produce suggestions, but only exact identity or explicit coach
selection resolves a publication reference.

### 20.4 Domain validation

Domain validation checks:

- required workout fields;
- required and forbidden fields per section format;
- valid nesting;
- supported exercise parameters;
- set/progression consistency;
- group membership;
- note visibility rules;
- score/timer compatibility;
- scale variation validity;
- materialization compatibility;
- execution-sequence compatibility;
- stable ordering and coordinates.

### 20.5 Canonicalization

Canonicalization:

- applies canonical token spellings;
- normalizes compatible units;
- expands linear progression to concrete sets;
- resolves stable entity references;
- derives legacy-compatible uniform sets where required;
- orders unordered metadata deterministically;
- preserves authored item order;
- preserves authored notes verbatim;
- does not invent missing meaning.

---

## 21. Diagnostics

Diagnostics have severity:

- `error`: blocks preview conversion or publication;
- `warning`: valid but potentially unintended or deprecated;
- `information`: optional guidance.

Diagnostics have stable semantic codes and parameters so the UI can localize
them according to ADR-048.

Examples:

```text
DSL_UNKNOWN_KEY
DSL_MISSING_REQUIRED_FIELD
DSL_UNCLOSED_BLOCK
DSL_INVALID_NESTING
DSL_AMBIGUOUS_EXERCISE
DSL_UNKNOWN_EXERCISE
DSL_UNSUPPORTED_EXERCISE_PARAMETER
DSL_INCOMPATIBLE_UNIT
DSL_PROGRESSION_SET_COUNT_MISMATCH
DSL_INVALID_REST_SCOPE
DSL_FORMAT_SETTING_NOT_ALLOWED
DSL_SCORE_FORMAT_MISMATCH
DSL_INACTIVE_SCALE_LEVEL
DSL_EXECUTION_SEQUENCE_INVALID
```

Each diagnostic includes:

- stable code;
- severity;
- localized display message at the presentation boundary;
- source start/end;
- owning block;
- canonical field if known;
- suggested replacements;
- optional safe edit;
- documentation anchor.

Example coach-facing message:

> The AMRAP section “Conditioning” needs a duration. Add `duration: 12 min`.

Another:

> “Squat” matches more than one exercise. Choose Back Squat, Front Squat, or
> Air Squat.

---

## 22. Tiptap Editor Experience

### 22.1 Familiar document surface

The editor should provide familiar tools where they do not conflict with
semantics:

- paragraphs;
- headings;
- bold;
- italic;
- underline;
- strike-through where useful;
- bullet lists;
- numbered lists;
- undo/redo;
- keyboard shortcuts;
- copy/paste;
- find;
- selection;
- links in notes;
- safe callouts;
- accessible keyboard navigation.

### 22.2 Semantic workout nodes

Tiptap custom nodes should represent:

- workout;
- section;
- exercise;
- header;
- group;
- scale variation;
- note;
- parameter;
- concrete set;
- diagnostic decoration.

The visual presentation may resemble normal text while the node model retains
stable semantic identity and scope.

### 22.3 Formatting boundary

Rich formatting is allowed broadly in titles, descriptions, and notes.
Executable meaning comes only from canonical fields and semantic nodes.

Images, tables, embeds, arbitrary layouts, or attachments may be permitted in
notes only after an explicit product decision. They are never parsed into
exercise/timer semantics. Unsafe HTML, scripts, remote embeds, and unsupported
paste content must be sanitized.

### 22.4 Slash commands and templates

Examples:

```text
/section
/amrap
/emom
/for-time
/exercise
/superset
/progression
/scale
/note
/header
/rest
```

A slash command inserts a valid canonical template with required fields and
places the caret at the next expected value.

---

## 23. Context-Aware Autocomplete and Inline Word Suggestions

Autocomplete is a primary product feature, not a later convenience. It reduces
syntax mistakes, teaches the canonical language, and makes Quick Text usable
without memorization.

### 23.1 Interaction model

Autocomplete should behave like a modern code/document editor:

- suggestions appear as the coach types;
- the list narrows and reorders after every character;
- a dropdown appears when several matches remain;
- the best inline completion may appear as faint “ghost text”;
- `Arrow Up` and `Arrow Down` navigate;
- `Enter` or `Tab` accepts;
- `Escape` dismisses;
- mouse/touch selection works;
- the active suggestion includes a short explanation and expected value;
- accepting a structural suggestion can insert a complete snippet;
- the system never silently accepts or rewrites a semantic value.

The UI should look like writing assistance, not a development tool.

### 23.2 Suggestion-source priority

Suggestions are ranked by semantic importance:

1. valid canonical DSL tokens for the current cursor context;
2. required parameters missing from the current block;
3. canonical enum values for the active parameter;
4. section formats and format-specific snippets;
5. exercise names and registered exercise aliases;
6. active scale levels;
7. units and measurement values;
8. note markers and group/header markers;
9. common workout-domain words;
10. general common words appropriate to authored notes.

Canonical suggestions must remain clearly distinguishable from ordinary word
suggestions.

### 23.3 Context-aware filtering

The suggestion engine understands the cursor scope.

Examples:

- after `[section:`, suggest only section formats;
- inside an AMRAP section, suggest `duration`, `score`, allowed rest settings,
  exercises, and notes;
- after `score:`, suggest score types valid for that format;
- after `[exercise:`, suggest exercise names;
- within Back Squat, suggest load/reps/tempo/RPE-related fields and not
  `distance` unless the catalog allows it;
- after `load:`, suggest compatible units and percentage modes;
- after `[scale:`, suggest active scale slugs;
- after `!`, suggest allowed note markers;
- inside a note paragraph, prefer common-language suggestions and suppress
  structural keys unless the coach explicitly invokes them.

### 23.4 Canonical vocabulary source

Canonical keyword suggestions must come from the same versioned registry used
by:

- the parser;
- the validator;
- the formatter;
- the help system;
- snippets;
- API schemas where applicable;
- tests.

The project must not maintain unrelated handwritten canonical word lists in
several components.

Each vocabulary entry should contain:

```text
canonical token
kind
valid scopes
value type
allowed/required formats
aliases
deprecation state
short localized help
long documentation anchor
snippet template
sorting weight
```

### 23.5 Exercise vocabulary

The exercise vocabulary contains:

- stable exercise ID;
- canonical display name;
- aliases;
- localized display aliases where supported;
- movement family;
- equipment;
- supported prescription dimensions;
- active/archive state;
- recent/frequent usage metadata for ranking.

Exercise matching may be fuzzy for the dropdown. Publication identity still
requires an exact underlying selection or unambiguous canonical match.

### 23.6 Common workout vocabulary

A larger versioned vocabulary may support ordinary words frequently used in
workout titles, subtitles, descriptions, and notes:

- movement and anatomy terms;
- coaching cues;
- intensity terms;
- tempo and pacing language;
- safety language;
- equipment terms;
- body positions;
- progression and deload terminology;
- common CrossFit, strength, gymnastics, aerobics, flexibility, and recovery
  phrases;
- common connecting words used in authored workout prose.

This vocabulary is a writing aid only. It does not create canonical semantics
unless the accepted suggestion is a registered DSL token or semantic entity.

For example, suggesting “controlled” in a note does not create a `tempo`
parameter. If the coach wants canonical tempo, the editor suggests and inserts
the `tempo:` field.

### 23.7 General-language suggestions

General word completion must be conservative:

- it is active primarily in titles, subtitles, descriptions, and notes;
- it does not replace browser spellcheck automatically;
- it does not rewrite exercise names or canonical tokens;
- it never changes text without explicit acceptance;
- it respects the user's selected language;
- it can be disabled independently from canonical DSL completion;
- it avoids transmitting private workout drafts to external services.

The initial implementation should prefer a local, self-hosted vocabulary and
ranking index. No third-party cloud writing assistant should receive workout
content.

### 23.8 Ranking

Candidate ranking may consider:

- exact prefix;
- canonical-token priority;
- validity in current scope;
- required-but-missing field priority;
- exercise capability compatibility;
- recent coach usage;
- frequent gym-wide usage;
- edit distance for dropdown suggestions;
- selected locale;
- active versus archived entity;
- deprecated alias penalty.

Ranking must not change canonical meaning. It changes only presentation order.

### 23.9 Incremental updates

As each character is typed:

1. cancel or supersede the stale suggestion request;
2. update the local parse context;
3. filter valid canonical candidates;
4. query the local exercise/common-word index;
5. merge and rank candidates;
6. update the dropdown without moving the caret;
7. retain keyboard selection where possible.

The interaction target should feel immediate. Canonical and locally cached
suggestions should not depend on a network request.

### 23.10 Offline behavior

The editor should retain:

- canonical DSL vocabulary;
- format snippets;
- units and enums;
- a cached active exercise catalog;
- a common workout-word dictionary;
- relevant localized help labels.

Offline autocomplete may omit remote freshness but must remain functional.
Publication still follows the established online/offline command policy.

### 23.11 Accessibility

The autocomplete component must follow accessible combobox/listbox behavior:

- correct ARIA roles and active-descendant handling;
- screen-reader announcement of result count and active result;
- full keyboard operation;
- visible focus;
- no color-only distinction between candidate types;
- touch-friendly target sizes;
- correct RTL layout for Arabic and Hebrew.

---

## 24. Canonical Formatter and Beautification

The canonical formatter outputs:

- canonical keyword spelling;
- canonical block markers;
- stable field order;
- stable spacing;
- normalized units;
- normalized duration presentation;
- readable blank lines;
- authored item order;
- canonical note placement;
- explicit progression;
- explicit scope;
- no hidden semantic changes.

Example input:

```text
[exercise: back squat]
prescription:5x3@80%
rest-between-sets:2m
[/exercise]
```

Possible canonical output:

```text
[exercise: Back Squat]
sets: 5
reps: 3
load: 80 %1rm
rest-between-sets: 2 min
[/exercise]
```

The “Beautify” action:

1. parses current source;
2. blocks if parsing or validation fails;
3. shows a before/after diff when meaningful;
4. replaces source only after coach confirmation if the change is substantial;
5. preserves the same canonical workout;
6. remains undoable.

The visual workout preview is rendered from the canonical model, not from
Tiptap HTML.

---

## 25. Save, Preview, and Publish

### 25.1 Autosave

Autosave retains:

- raw Quick Text/Tiptap source;
- DSL version;
- editor mode;
- source revision;
- diagnostics summary;
- last valid parsed canonical draft where useful;
- timestamps and existing audit metadata.

Invalid source is a valid autosaved draft state.

### 25.2 Preview

Preview requires a valid canonical parse. It shows:

- canonical workout view;
- sections and nested sections;
- headers;
- groups;
- concrete sets;
- notes according to current admin permissions;
- scale-materialized tabs;
- timer/execution outline;
- scoring behavior;
- estimated duration where derivable.

### 25.3 Publish gate

Publish performs authoritative backend:

1. DSL version validation;
2. parse;
3. reference resolution;
4. canonicalization;
5. complete domain validation;
6. materialization validation;
7. timer/checklist sequence validation;
8. revision/concurrency validation;
9. persistence through the existing Workouts command/adapter boundary.

Warnings may require acknowledgement according to severity policy. Errors
always block publication.

### 25.4 Source retention

The application should retain the original or canonicalized Quick Text source
with the draft revision for continued editing. Published consumers receive
canonical workout data and do not reparse this source.

---

## 26. Versioning and Evolution

Every document declares:

```text
dsl-version: 1
```

Rules:

- version meaning is immutable;
- additive canonical keys may be introduced when old parsers can reject them
  safely;
- breaking grammar changes require a new DSL version;
- the formatter targets an explicit version;
- drafts retain their authored version;
- migrations transform source explicitly and preview changes;
- deprecated tokens remain registered for a defined compatibility window;
- the parser reports unsupported future versions clearly;
- canonical schema version and DSL version are related but not assumed to be
  identical.

Grammar and vocabulary changes require:

- ADR or accepted amendment;
- parser/formatter update;
- conformance fixtures;
- autocomplete registry update;
- manual update;
- migration/compatibility notes.

---

## 27. Security, Privacy, and Resource Limits

The editor and parser must:

- sanitize pasted HTML;
- reject script and executable embed content;
- prevent stored XSS in notes and titles;
- enforce source and node-count limits;
- enforce nesting-depth limits;
- enforce note-length and field-length limits;
- avoid catastrophic parser backtracking;
- avoid external cloud completion services by default;
- preserve tenant/context authorization;
- never expose hidden coach-only notes to athletes;
- validate entity IDs and active state on the backend;
- treat client-hidden semantic metadata as untrusted input;
- rate-limit expensive parse/preview endpoints where necessary.

The grammar should be designed for linear or predictably bounded parsing.

---

## 28. Testing Strategy

### 28.1 Case-by-case coverage matrix

Maintain an authoritative matrix:

| Area | Cases | Canonical model | DSL | Validation | Formatter | Tests | Docs |
|---|---:|---:|---:|---:|---:|---:|---:|
| Workout metadata | required | required | required | required | required | required | required |
| Notes | required | required | required | required | required | required | required |
| Headers/subtitles | required | required | required | required | required | required | required |
| Every section format | required | required | required | required | required | required | required |
| Exercise parameters | required | required | required | required | required | required | required |
| Uniform sets | required | required | required | required | required | required | required |
| Explicit sets | required | required | required | required | required | required | required |
| Progression/deload | required | required | required | required | required | required | required |
| Rest types | required | required | required | required | required | required | required |
| Groups | required | required | required | required | required | required | required |
| Scale variations | required | required | required | required | required | required | required |
| Scores/timers | required | required | required | required | required | required | required |
| Autocomplete | n/a | registry | required | contextual | n/a | required | required |

A row is complete only when all applicable columns are complete.

### 28.2 Parser unit tests

Pure domain tests cover:

- every valid construct;
- every delimiter;
- whitespace and Unicode normalization;
- multiline notes;
- nested blocks;
- malformed blocks;
- error recovery;
- exact source spans;
- aliases and deprecations;
- unit conversion;
- compact prescription notation.

### 28.3 Validation tests

Pure domain tests cover:

- required/optional/forbidden fields for every format;
- parameter scope;
- exercise capabilities;
- set counts;
- progression;
- load units;
- rest semantics;
- groups;
- headers;
- notes;
- scales;
- scores;
- timer compatibility;
- execution-sequence construction.

### 28.4 Golden conformance corpus

Create versioned fixtures containing:

- valid source;
- expected canonical AST/map;
- expected formatted source;
- expected diagnostics;
- invalid source and exact errors.

The same fixtures should test backend and frontend parsing assistance if both
runtimes contain parser logic.

### 28.5 Round-trip and property tests

Required properties include:

```text
parse(format(canonical)) == canonical
format(parse(formatted_source)) == formatted_source
canonicalize(canonicalize(value)) == canonicalize(value)
```

Generated tests should exercise:

- different section combinations;
- arbitrary per-set values;
- nested sections;
- notes;
- Unicode exercise/title text;
- scale overrides;
- group expansion;
- compatible unit forms.

### 28.6 Mode parity tests

For every canonical fixture:

1. load it in Structured mode;
2. serialize to Quick Text;
3. parse it;
4. switch back to Structured mode;
5. assert semantic equality.

### 28.7 Autocomplete tests

Test:

- candidate source priority;
- cursor context;
- required-field ranking;
- incremental narrowing;
- exercise ambiguity;
- canonical versus common-word distinction;
- keyboard acceptance/dismissal;
- snippets;
- deprecated tokens;
- offline vocabulary;
- locale and RTL behavior;
- accessibility roles and announcements;
- stale async result cancellation.

### 28.8 Integration and live tests

Integration tests use the real database for draft/publish behavior. Controller
tests use `ConnCase` and validate the OpenAPI contract.

Live tests include:

- typing every section format from a template;
- authoring a complex progression and deload;
- resolving an ambiguous exercise;
- correcting syntax and semantic errors;
- switching both directions between modes;
- beautifying;
- previewing all scale instances;
- publishing;
- executing the published workout;
- reopening a published workout revision;
- using Quick Text inside embedded personal assignment;
- keyboard-only and mobile authoring;
- offline draft and autocomplete behavior.

---

## 29. Coach Manual and Learning System

A complete coach manual is required and ships with the feature.

### 29.1 Manual structure

1. What Quick Text is.
2. Five-minute quick start.
3. Document structure.
4. Workout title, subtitle, and metadata.
5. Sections and the canonical section template.
6. One chapter per section format.
7. Adding exercises.
8. Uniform and per-set prescriptions.
9. Linear progression.
10. Arbitrary progression and deload.
11. Rest types.
12. Supersets and alternating groups.
13. Headers.
14. Notes and visibility.
15. Scale variations.
16. Scores, timers, and WOD settings.
17. Autocomplete and keyboard shortcuts.
18. Beautify and preview.
19. Switching between Quick Text and Structured.
20. Error messages and corrections.
21. Complete examples.
22. Canonical vocabulary reference.
23. Printable cheat sheet.

### 29.2 Example library

Provide copyable, valid templates for:

- simple strength workout;
- linear load progression;
- arbitrary load progression with deload;
- superset;
- alternating group;
- AMRAP;
- EMOM;
- complex EMOM;
- even/odd;
- for time;
- Tabata;
- custom HIIT;
- Billat;
- cluster sets;
- HRR;
- ascending and descending ladders;
- pyramid;
- calorie target;
- death by;
- recovery/mobility;
- workout with multiple scale variations;
- nested sections;
- section/exercise/header notes.

### 29.3 Inline learning

The editor is also an interactive manual:

- `/` opens templates;
- `Ctrl+Space` opens contextual suggestions;
- hover/focus help explains a token;
- missing required fields appear at the top of suggestions;
- diagnostics link to the relevant manual anchor;
- accepted snippets contain placeholder hints;
- a “Show example” action inserts or previews a canonical example;
- a “Why is this invalid?” panel distinguishes syntax from workout rules.

---

## 30. Recommended Delivery Sequence

This feature is large enough to require a dedicated implementation plan and one
or more ADRs. A safe sequence is:

1. Inventory the exact current canonical workout schema and format registry.
2. Build the exhaustive coverage matrix.
3. Resolve canonical model gaps before designing syntax for them.
4. Write the DSL/versioning/parser ADR.
5. Write the Tiptap/editor/autocomplete dependency and architecture ADR.
6. Define the formal grammar and vocabulary registry.
7. Write the coach manual examples as executable conformance fixtures.
8. Implement pure lexer/parser diagnostics with TDD.
9. Implement pure canonical validation and canonicalization with TDD.
10. Implement the canonical formatter and round-trip tests.
11. Add contract-first parse/preview/publish APIs where needed.
12. Integrate Tiptap semantic nodes.
13. Implement canonical autocomplete and snippets.
14. Implement exercise and common-word suggestion indexes.
15. Add Structured/Quick Text mode conversion and parity tests.
16. Add preview, beautify, and publish gates.
17. Complete accessibility, localization, offline, security, and performance
    verification.
18. Perform all format-by-format live tests.
19. Update ADR Implementation Notes and technical debt.

No parser or editor dependency should be implemented before the inventory,
coverage matrix, canonical-gap decisions, and ADRs are accepted.

---

## 31. Open Decisions for the ADR Phase

The following require explicit resolution before implementation:

1. Final product-facing name for Quick Text.
2. Exact textual block delimiters.
3. Whether `rounds` and `straight-sets` are canonical formats or authoring
   composition settings over an existing timer format.
4. Authoritative parser implementation strategy across Elixir and TypeScript.
5. Tiptap dependency and exact extension set.
6. Storage representation for Tiptap source: JSON document, canonical DSL text,
   or both.
7. Note rich-text representation and safe supported marks.
8. Complete canonical note-type and visibility registry.
9. Complete exercise capability registry.
10. Rest inheritance and precedence.
11. Progression rounding policy.
12. Canonical duration and unit formatting.
13. Decimal separator input policy by locale.
14. Comment syntax and whether comments are retained through formatting.
15. Canonical/common-word vocabulary storage and update mechanism.
16. Personal/recent suggestion ranking and privacy policy.
17. Maximum source size, nesting depth, and suggestion-index size.
18. Warning acknowledgement policy at publication.
19. DSL version migration and deprecation windows.
20. Whether source formatting changes require an explicit diff confirmation.

---

## 32. Acceptance Criteria

The design is complete only when:

- both modes produce the same canonical model;
- every canonical workout field has a DSL representation or an explicitly
  documented server-managed reason not to have one;
- every section format has an independent syntax/validation/formatter/test/docs
  specification;
- notes, headers, subtitles, progression, deload, arbitrary per-set values,
  rest types, groups, scales, scores, timers, and WOD settings are covered;
- unknown and ambiguous source cannot be published;
- syntax and semantic errors are distinguished;
- formatting is round-trip safe;
- autocomplete covers canonical tokens, exercises, units, enums, scales,
  common workout vocabulary, and ordinary note/title vocabulary;
- suggestion lists narrow continuously as the coach types;
- canonical suggestions are context-aware and take priority;
- the coach can use Quick Text without programming knowledge;
- the manual, cheat sheet, snippets, and examples are complete;
- all behavior complies with the Workouts bounded context, hexagonal
  architecture, contract-first API, localization, revision, materialization,
  and execution decisions already accepted by the project.
