# ADR-069: Canonical Workout DSL and Assisted Authoring
Date: 2026-07-31
Status: Accepted

## Context

Workout authoring currently uses one structured canvas backed by durable
`draft_data` and an explicit publish/materialization boundary. Coaches also
need a faster document-like authoring mode without introducing a second
published workout model or relying on ambiguous natural-language inference.

The text mode must express the complete canonical workout model, including all
section formats, headers, notes, concrete per-set prescriptions, progressive
loading and deloading, groups, scale variations, score settings, and timers.
It must also be practical for non-technical coaches through contextual
autocomplete, templates, live diagnostics, and canonical beautification.

The existing format vocabulary is already consumed by authoring, validation,
execution, and frontend presentation. Hand-maintaining another independent
format or keyword list would create drift. The current worktree also contains
the additive structured-set implementation from ADR-068, which this decision
must preserve.

## Decision

Add a versioned, deterministic, line-oriented workout DSL as a second
authoring interface over the existing canonical workout draft.

The structured canvas remains the reference editor and the published
canonical workout remains the sole source of truth. Quick Text source is a
recoverable draft artifact; publication always reparses and validates it on
the backend before using the existing Workouts publish/materialization path.

Implement the authoritative lexer/parser, canonicalizer, validator, and
formatter as pure Elixir domain modules within `MilosTraining.Workouts.Domain`.
The parser returns canonical draft maps plus structured, source-positioned
diagnostics. It does not access Ecto, Phoenix, HTTP, search infrastructure, or
the exercise database.

Use a shared pure domain vocabulary registry as the source for parser tokens,
formatter ordering, required format fields, help metadata, and frontend
autocomplete data. `TimerConfig` delegates its supported-format and
required/optional-field knowledge to this registry rather than retaining a
second list.

Use Tiptap for the Quick Text browser editor. It presents a familiar
word-processor surface while allowing semantic workout nodes and contextual
suggestion extensions. Canonical DSL text is the parseable Quick Text draft
source. Tiptap JSON may be retained as a presentation cache with a source hash,
but it is never an independently authoritative workout representation.

Autocomplete has two explicitly separated sources:

1. canonical structural vocabulary, format-specific parameters, enums, units,
   active scale levels, and exercise suggestions;
2. non-semantic common workout/general words for titles, subtitles, and notes.

Only canonical suggestions create workout semantics. Common-word suggestions
never silently create parameters or change the canonical model. Suggestions
are local/cached and continuously narrowed as the user types; no third-party
cloud writing service receives draft content.

The first implementation slice establishes the registry, parser,
canonicalizer, formatter, conformance tests, and parse/preview boundary before
the full Tiptap surface. Subsequent slices add the editor, autocomplete
providers, complete format templates, and the coach manual against the same
registry and fixtures.

## Rationale

One canonical model preserves existing materialization, assignment, execution,
history, and modification-patch semantics. A deterministic grammar converts
author convenience into certainty: invalid or ambiguous source is saved as a
draft but cannot be published.

An authoritative backend parser prevents client behavior from becoming a
publication trust boundary. Keeping parsing and formatting pure follows the
hexagonal architecture and makes exhaustive unit and property testing
possible.

A shared vocabulary registry prevents the format discrepancy already found
between early product prose and the current nineteen backend formats.
Contextual completion and snippets let strict syntax remain usable by coaches
without requiring them to memorize a programming language.

Tiptap is schema-driven, extensible, and capable of conventional rich-text
interaction. Using it only at the interface layer keeps the domain independent
of the editor dependency.

## Alternatives Considered

Parsing arbitrary natural language, with or without an LLM, was rejected
because publication meaning would be probabilistic and ambiguous.

Maintaining text workouts as a separate aggregate was rejected because
structured and text authoring would diverge and every downstream consumer
would need two models.

Treating Tiptap JSON as the canonical workout was rejected because editor
presentation nodes are not the domain contract and would couple backend
business rules to one browser library.

Implementing the authoritative parser only in TypeScript was rejected because
the client is untrusted and publication must remain correct for every client.

Duplicating a complete parser in Elixir and TypeScript by hand was rejected
because grammar and diagnostics would drift. The frontend may perform
lightweight incremental token/context analysis for immediate assistance, but
the backend result is authoritative and both sides consume the same vocabulary
and conformance fixtures.

Using Meilisearch or a cloud service for every keystroke was rejected because
canonical completion must be immediate, private, and usable offline.

## Consequences

The Workouts context gains a stable DSL/version contract and pure domain
modules. Grammar changes require versioning, conformance fixtures, formatter
updates, autocomplete updates, and documentation updates.

Draft payloads may carry authoring mode, DSL source, and an optional editor
document cache without a new database table because `draft_data` already owns
incomplete authoring state. Published workout tables remain canonical.

New parse/preview endpoints, if introduced, must be specified in OpenAPI before
controllers. They call Workouts public APIs or an application service and
never call domain modules directly from controllers.

Tiptap and its selected extensions are approved new frontend dependencies for
this feature. Their bundle size, sanitization behavior, accessibility, and
license must be verified during implementation.

Exercise names are currently authored strings rather than references to a
dedicated exercise-catalog entity. Initial autocomplete can use curated and
previously authored names, but stable exercise IDs require a separate
canonical exercise-catalog design and additive schema change before they can
be guaranteed.

Invalid Quick Text remains autosavable. Preview, mode conversion to Structured,
and publication require a valid canonical result.

## Implementation Notes

Both implementation phases were completed on 2026-07-31.

Phase 1 established the canonical language and safe preview boundary:

- `MilosTraining.Workouts.Domain.WorkoutDsl` provides a deterministic,
  line-oriented parser, canonicalizer, validator, and formatter with
  source-positioned diagnostics and bounded source/document sizes.
- `WorkoutDsl.Vocabulary` is the single registry for the nineteen canonical
  section formats, aliases, required and optional timer fields, DSL tokens,
  note markers, enums, units, contextual completion metadata, and the
  code-backed exercise catalog. `TimerConfig`, templates, the manual, and the
  frontend consume that registry instead of maintaining parallel lists.
- The grammar covers workout and section metadata, nested sections, headers
  and subtitles, typed notes, exercises, composition groups, scale
  variations, uniform and concrete per-set prescriptions, bodyweight and
  percentage loads, linear and arbitrary progressions/deloads, tempo, pace,
  cadence, range-of-motion and equipment tweaks, typed rest, score settings,
  and all timer-specific parameters.
- `POST /api/admin/workouts/dsl/parse` is an admin-only, contract-first
  Application-service boundary. Invalid or ambiguous input remains savable but
  cannot cross preview, conversion, or publication boundaries.

Phase 2 completed durable authoring and publication:

- Drafts retain `authoring_mode`, DSL version/source, optional sanitized
  Tiptap JSON, the latest diagnostics, and a monotonically increasing source
  revision. Autosave uses optimistic revision checks so two tabs cannot
  silently overwrite one another.
- Tiptap supplies a familiar document surface with headings, emphasis,
  underline, strike-through, highlighting, lists, quotes, code blocks,
  alignment, links, undo/redo, spellcheck, character limits, and sanitized
  HTML paste. The editor is read-only until the exact server revision has
  loaded, preventing late-load overwrites.
- Contextual completion continuously narrows canonical tokens, parameters,
  enum values, section templates, exercise catalog names/aliases, and
  non-semantic common words. Slash commands insert registry-generated,
  parseable section templates.
- The generated coach manual and all nineteen format templates come from the
  same registry used by parsing. The in-app manual, static Greek guide,
  vocabulary endpoint, and conformance tests therefore fail together rather
  than drifting independently.
- Beautify reparses and replaces the source with the canonical formatter
  output. Conversion to Structured mode and direct publication use the same
  canonical draft model.
- Direct publication first saves the exact editor snapshot, verifies its
  revision under a row lock, reparses it, requires explicit warning
  acknowledgement, performs an execution/timer dry-run, and only then invokes
  the existing Workouts publication/materialization path.
- OpenAPI request/response schemas and the generated TypeScript contract expose
  the revisioned authoring state, diagnostics, preflight result, manual,
  vocabulary, and publication result.

Final verification included 43 focused backend tests covering the nineteen
templates, parse-format-parse idempotence, rich nested/group/scale programs,
randomized prescription combinations, source and capability limits,
manual/vocabulary synchronization, timer construction, stale revisions, and
warning acknowledgement. The affected workout creation suite passes 5/5,
compilation with warnings as errors succeeds, and
`mix milos.architecture` reports clean boundaries.

The frontend passes 26 Vitest files / 96 tests, TypeScript, ESLint, and a full
Next.js production build. Playwright verifies load, preview, Beautify,
Structured conversion, revisioned autosave, and exact-revision direct publish
in desktop and mobile Chromium (4/4 flows). All 2,468 messages remain
locale-parity valid. Generated OpenAPI files were produced from an isolated
committed worktree so unrelated concurrent endpoints were not folded into
this feature.

The complete clean committed backend suite ran 484 tests: 483 passed and the
sole failure is the pre-existing Gamification
`AdminChallengeControllerTest` overlap-limit expectation, outside the Workouts
context and unchanged by this feature. All Quick Text, Workouts creation,
compilation, architecture, contract, frontend, build, and browser gates are
green.

TD-036 is resolved. No part of the agreed Quick Text DSL, assisted authoring,
canonical beautification, or safe publication surface remains deferred.
